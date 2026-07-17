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

    let fiveHour: LegacyWindow?
    let sevenDay: LegacyWindow?
    let limits: [Limit]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case limits
    }
}

extension ClaudeUsageResponse {
    /// Maps the response to provider-agnostic windows. Unknown limit kinds
    /// are skipped so future server-side additions never break parsing.
    func usageWindows() -> [UsageWindow] {
        if let limits, !limits.isEmpty {
            let mapped = limits.compactMap { $0.usageWindow() }
            if !mapped.isEmpty {
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
