import Foundation

/// Wire format of `GET https://chatgpt.com/backend-api/wham/usage`, the
/// request the Codex CLI's `/status` sends (its schema is public in
/// codex-rs/codex-backend-openapi-models). Undocumented and unstable:
/// every endpoint-specific detail stays in this file and
/// `CodexProvider`. Decoded with `.convertFromSnakeCase`.
struct CodexUsageResponse: Decodable {
    struct Window: Decodable {
        let usedPercent: Double?
        let limitWindowSeconds: Double?
        let resetAfterSeconds: Double?
        /// Unix epoch seconds.
        let resetAt: Double?
    }

    struct RateLimit: Decodable {
        let allowed: Bool?
        let limitReached: Bool?
        let primaryWindow: Window?
        let secondaryWindow: Window?
    }

    /// A model-specific limit beside the overall ones (GPT-5.3-Codex-Spark).
    struct AdditionalRateLimit: Decodable {
        let limitName: String?
        let meteredFeature: String?
        let rateLimit: RateLimit?
    }

    struct SpendControl: Decodable {
        struct IndividualLimit: Decodable {
            let limit: Double?
            let used: Double?
            let remainingPercent: Double?
            let resetAt: Double?
        }

        let reached: Bool?
        let individualLimit: IndividualLimit?
    }

    let planType: String?
    let accountId: String?
    let rateLimit: RateLimit?
    let additionalRateLimits: [AdditionalRateLimit]?
    let spendControl: SpendControl?

    static func decode(_ data: Data) throws -> CodexUsageResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CodexUsageResponse.self, from: data)
    }
}

extension CodexUsageResponse {
    /// Under this length a primary window is a session; from it on, the
    /// overall period (Free's 30 days has no session at all).
    static let sessionMaxDuration: TimeInterval = 24 * 3600

    /// Maps the response to provider-agnostic windows. The primary window
    /// is the session when it is short (5 h on paid plans) and the overall
    /// period when it is long (Codex Free: one 30-day window); the
    /// secondary is the week. Each additional, model-specific limit gives
    /// one per-model window, its weekly one by preference. A limit the
    /// server flags reached marks its full windows exceeded. Windows
    /// without a figure are skipped.
    func usageWindows(now: Date = Date()) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        let exceeded = rateLimit?.limitReached == true
        if let primary = rateLimit?.primaryWindow {
            let kind: UsageWindow.Kind = (primary.limitWindowSeconds ?? 0) <= Self.sessionMaxDuration ? .session : .weekly
            if let window = Self.window(primary, kind: kind, exceeded: exceeded, now: now) {
                windows.append(window)
            }
        }
        if let secondary = rateLimit?.secondaryWindow {
            // Never seen beside a long primary; keyed apart if it ever is.
            let kind: UsageWindow.Kind = windows.contains { $0.kind == .weekly } ? .quota("secondary_window") : .weekly
            if let window = Self.window(secondary, kind: kind, exceeded: exceeded, now: now) {
                windows.append(window)
            }
        }
        for extra in additionalRateLimits ?? [] {
            guard let name = extra.limitName, !name.isEmpty,
                  let source = extra.rateLimit?.secondaryWindow ?? extra.rateLimit?.primaryWindow,
                  let window = Self.window(source, kind: .modelSpecific(name), exceeded: extra.rateLimit?.limitReached == true, now: now)
            else { continue }
            windows.append(window)
        }
        return windows
    }

    private static func window(_ wire: Window, kind: UsageWindow.Kind, exceeded: Bool, now: Date) -> UsageWindow? {
        guard let percent = wire.usedPercent else { return nil }
        let resetsAt = wire.resetAt.map { Date(timeIntervalSince1970: $0) }
            ?? wire.resetAfterSeconds.map { now.addingTimeInterval($0) }
        return UsageWindow(
            kind: kind,
            usedPct: percent,
            resetsAt: resetsAt,
            severity: exceeded && percent >= 100 ? .exceeded : nil,
            duration: wire.limitWindowSeconds.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    /// A workspace's individual spend limit, when the plan has one;
    /// personal plans report none. Amounts are in USD.
    func spendStatus() -> SpendStatus? {
        guard let limit = spendControl?.individualLimit, limit.limit != nil || limit.used != nil || limit.remainingPercent != nil else {
            return nil
        }
        var percent = limit.remainingPercent.map { max(0, min(100, 100 - $0)) }
        if percent == nil, let used = limit.used, let cap = limit.limit, cap > 0 {
            percent = max(0, min(100, used / cap * 100))
        }
        return SpendStatus(
            enabled: true,
            percent: percent,
            severity: spendControl?.reached == true ? .exceeded : nil,
            usedAmount: limit.used,
            limitAmount: limit.limit,
            currency: "USD"
        )
    }
}
