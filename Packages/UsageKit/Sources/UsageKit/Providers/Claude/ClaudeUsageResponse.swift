import Foundation

/// Wire format of `GET https://api.anthropic.com/api/oauth/usage`.
/// Undocumented and unstable: every endpoint-specific detail stays in this
/// file and `ClaudeProvider`. The modern shape is the `limits` array; the
/// top-level `five_hour`/`seven_day` objects are a legacy fallback.
struct ClaudeUsageResponse: Decodable {
    struct LegacyWindow: Decodable {
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    struct Limit: Decodable {
        struct Scope: Decodable {
            struct Model: Decodable {
                let id: String?
                let displayName: String?

                enum CodingKeys: String, CodingKey {
                    case id
                    case displayName = "display_name"
                }
            }

            let model: Model?
        }

        let kind: String?
        let percent: Double?
        let severity: String?
        let resetsAt: String?
        let scope: Scope?
        let isActive: Bool?

        enum CodingKeys: String, CodingKey {
            case kind, percent, severity, scope
            case resetsAt = "resets_at"
            case isActive = "is_active"
        }
    }

    /// `{"amount_minor": 1076, "currency": "USD", "exponent": 2}` → 10.76.
    struct Money: Decodable {
        let amountMinor: Double?
        let currency: String?
        let exponent: Int?

        enum CodingKeys: String, CodingKey {
            case amountMinor = "amount_minor"
            case currency, exponent
        }

        var majorAmount: Double? {
            amountMinor.map { $0 / pow(10, Double(exponent ?? 2)) }
        }
    }

    struct Spend: Decodable {
        let used: Money?
        let limit: Money?
        let percent: Double?
        let severity: String?
        let enabled: Bool?
    }

    struct ExtraUsage: Decodable {
        let isEnabled: Bool?
        let monthlyLimit: Double?
        let usedCredits: Double?
        let utilization: Double?
        let currency: String?
        let decimalPlaces: Int?

        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case monthlyLimit = "monthly_limit"
            case usedCredits = "used_credits"
            case decimalPlaces = "decimal_places"
            case utilization, currency
        }
    }

    let fiveHour: LegacyWindow?
    let sevenDay: LegacyWindow?
    let limits: [Limit]?
    let spend: Spend?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case extraUsage = "extra_usage"
        case limits, spend
    }
}

extension ClaudeUsageResponse {
    /// Maps the response to provider-agnostic windows. Unknown limit kinds
    /// are skipped so future server-side additions never break parsing.
    func usageWindows() -> [UsageWindow] {
        if let limits, !limits.isEmpty {
            var mapped = limits.compactMap { $0.usageWindow() }
            if !mapped.isEmpty {
                alignScopedWeeklyResets(&mapped)
                return mapped
            }
        }

        var windows: [UsageWindow] = []
        if let fiveHour, let pct = fiveHour.utilization {
            windows.append(UsageWindow(
                kind: .session,
                usedPct: pct,
                resetsAt: ClaudeUsageResponse.parseDate(fiveHour.resetsAt)
            ))
        }
        if let sevenDay, let pct = sevenDay.utilization {
            windows.append(UsageWindow(
                kind: .weekly,
                usedPct: pct,
                resetsAt: ClaudeUsageResponse.parseDate(sevenDay.resetsAt)
            ))
        }
        return windows
    }

    /// The scoped weekly windows (per-model) reset together with the
    /// overall weekly window, but the endpoint reports timestamps a few
    /// microseconds apart. Share the weekly date so every surface shows
    /// the identical "resets in".
    private func alignScopedWeeklyResets(_ windows: inout [UsageWindow]) {
        guard let weeklyReset = windows.first(where: { $0.kind == .weekly })?.resetsAt else {
            return
        }
        for index in windows.indices {
            if case .modelSpecific = windows[index].kind {
                windows[index].resetsAt = weeklyReset
            }
        }
    }

    /// Maps the wire `spend` object; nil when the endpoint omits it.
    func spendStatus() -> SpendStatus? {
        guard let spend else { return nil }
        return SpendStatus(
            enabled: spend.enabled ?? false,
            percent: spend.percent,
            severity: spend.severity.flatMap(UsageWindow.Severity.init(rawValue:)),
            usedAmount: spend.used?.majorAmount,
            limitAmount: spend.limit?.majorAmount,
            currency: spend.used?.currency ?? spend.limit?.currency
        )
    }

    /// Maps the wire `extra_usage` object; credit amounts arrive in minor
    /// units scaled by `decimal_places`.
    func extraUsageStatus() -> ExtraUsageStatus? {
        guard let extraUsage else { return nil }
        let scale = pow(10, Double(extraUsage.decimalPlaces ?? 2))
        return ExtraUsageStatus(
            enabled: extraUsage.isEnabled ?? false,
            usedCredits: extraUsage.usedCredits.map { $0 / scale },
            monthlyLimit: extraUsage.monthlyLimit.map { $0 / scale },
            utilization: extraUsage.utilization,
            currency: extraUsage.currency
        )
    }

    /// resets_at is ISO 8601, usually with fractional seconds.
    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

extension ClaudeUsageResponse.Limit {
    func usageWindow() -> UsageWindow? {
        guard let percent else { return nil }

        let mappedKind: UsageWindow.Kind
        switch kind {
        case "session":
            mappedKind = .session
        case "weekly_all":
            mappedKind = .weekly
        case "weekly_scoped":
            guard let model = scope?.model?.displayName else { return nil }
            mappedKind = .modelSpecific(model)
        default:
            return nil
        }

        return UsageWindow(
            kind: mappedKind,
            usedPct: percent,
            resetsAt: ClaudeUsageResponse.parseDate(resetsAt),
            severity: severity.flatMap(UsageWindow.Severity.init(rawValue:)),
            isActive: isActive
        )
    }
}
