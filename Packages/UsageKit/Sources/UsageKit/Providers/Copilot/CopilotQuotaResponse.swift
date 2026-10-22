import Foundation

/// Wire format of `GET https://api.github.com/copilot_internal/user`, the
/// request Copilot's editor plug-ins send for the account's monthly
/// quotas. Undocumented and unstable: every endpoint-specific detail
/// stays in this file and `CopilotProvider`. Only the fields read are
/// declared; the snapshots are keyed by GitHub's own quota ids
/// (`premium_interactions`, `chat`, `completions`), which are what a
/// `.quota` window carries. Shape measured on a Free account on
/// 2026-10-20 (`Tests/UsageKitTests/Fixtures/copilot-quota-response.json`).
struct CopilotQuotaResponse: Decodable {
    struct Snapshot: Decodable {
        let entitlement: Double?
        let remaining: Double?
        let percentRemaining: Double?
        let unlimited: Bool?
        /// False for a quota the plan doesn't have at all (Free's premium
        /// requests: entitlement 0, percent remaining 0), which is not a
        /// window.
        let hasQuota: Bool?
        let overagePermitted: Bool?
        let overageCount: Double?

        enum CodingKeys: String, CodingKey {
            case entitlement, remaining, unlimited
            case percentRemaining = "percent_remaining"
            case hasQuota = "has_quota"
            case overagePermitted = "overage_permitted"
            case overageCount = "overage_count"
        }
    }

    /// The GitHub user's numeric id: the login's identity across devices.
    let id: Int?
    let copilotPlan: String?
    /// The plan as GitHub bills it (`free_limited_copilot`), which says
    /// Free where `copilot_plan` says "individual".
    let accessTypeSku: String?
    /// "2026-11-01" (midnight UTC on the first of the month), or a full
    /// ISO 8601 timestamp.
    let quotaResetDate: String?
    let quotaSnapshots: [String: Snapshot]?

    enum CodingKeys: String, CodingKey {
        case id
        case copilotPlan = "copilot_plan"
        case accessTypeSku = "access_type_sku"
        case quotaResetDate = "quota_reset_date"
        case quotaSnapshots = "quota_snapshots"
    }
}

extension CopilotQuotaResponse {
    /// The quotas in the order they are shown; any other id the endpoint
    /// adds follows, in name order.
    static let knownQuotas = ["premium_interactions", "chat", "completions"]

    /// Maps the metered quotas to windows: one `.quota` per snapshot the
    /// plan has (`has_quota`, an entitlement above zero) and doesn't mark
    /// unlimited (a paid plan's completions have nothing to meter), its
    /// figure from `percent_remaining` (else from the counts), its reset
    /// the month's and its length the month that ends there.
    func usageWindows() -> [UsageWindow] {
        guard let quotaSnapshots else { return [] }
        let resetsAt = quotaResetDate.flatMap(Self.parseDate)
        let duration = resetsAt.map(Self.monthLength(endingAt:))
        let order = Self.knownQuotas + quotaSnapshots.keys.filter { !Self.knownQuotas.contains($0) }.sorted()
        return order.compactMap { id -> UsageWindow? in
            guard let snapshot = quotaSnapshots[id], Self.isMetered(snapshot),
                  let usedPct = Self.usedPercent(of: snapshot) else { return nil }
            return UsageWindow(
                kind: .quota(id),
                usedPct: usedPct,
                resetsAt: resetsAt,
                severity: usedPct >= 100 ? .exceeded : nil,
                duration: duration
            )
        }
    }

    /// The account has no Copilot at all: its SKU says "no_access".
    var hasNoCopilot: Bool {
        accessTypeSku?.lowercased().contains("no_access") == true
    }

    /// What the quota fields said, for an answer with nothing to meter:
    /// "chat: has_quota true, unlimited false, 0/200; …", or "no
    /// quota_snapshots".
    var quotaSummary: String {
        guard let quotaSnapshots, !quotaSnapshots.isEmpty else {
            return "no quota_snapshots (sku \(accessTypeSku ?? "none"), plan \(copilotPlan ?? "none"))"
        }
        return quotaSnapshots.keys.sorted().map { id in
            let snapshot = quotaSnapshots[id]!
            func text(_ value: Bool?) -> String { value.map { $0 ? "true" : "false" } ?? "nil" }
            func number(_ value: Double?) -> String { value.map { String(Int($0)) } ?? "nil" }
            return "\(id): has_quota \(text(snapshot.hasQuota)), unlimited \(text(snapshot.unlimited)), \(number(snapshot.remaining))/\(number(snapshot.entitlement))"
        }.joined(separator: "; ")
    }

    /// A quota the plan actually meters: not unlimited, not absent.
    static func isMetered(_ snapshot: Snapshot) -> Bool {
        snapshot.unlimited != true && snapshot.hasQuota != false && (snapshot.entitlement ?? 0) > 0
    }

    /// `percent_remaining` when reported, else what the counts say; nil
    /// without an entitlement.
    static func usedPercent(of snapshot: Snapshot) -> Double? {
        if let remaining = snapshot.percentRemaining {
            return max(0, min(100, 100 - remaining))
        }
        guard let entitlement = snapshot.entitlement, entitlement > 0, let remaining = snapshot.remaining else { return nil }
        return max(0, min(100, (entitlement - remaining) / entitlement * 100))
    }

    /// The plan as the pill shows it. The SKU is the truth (a Free account
    /// reports `copilot_plan` "individual" beside `access_type_sku`
    /// `free_limited_copilot`, measured 2026-10-20); the paid SKUs are
    /// the community-reported ones, and `copilot_plan` stands in for an
    /// unknown SKU.
    var planName: String? {
        if let sku = accessTypeSku?.lowercased() {
            if sku.contains("free") { return "Free" }
            if sku.contains("pro_plus") { return "Pro+" }
            if sku.contains("individual") { return "Pro" }
            if sku.contains("business") { return "Business" }
            if sku.contains("enterprise") { return "Enterprise" }
        }
        switch copilotPlan {
        case nil: return accessTypeSku
        case "free": return "Free"
        case "individual": return "Pro"
        case "individual_pro": return "Pro+"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case let other?: return other
        }
    }

    /// A bare date is midnight UTC (GitHub resets monthly quotas at
    /// 00:00 UTC on the first); a timestamp is itself.
    static func parseDate(_ string: String) -> Date? {
        let timestamp = ISO8601DateFormatter()
        timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = timestamp.date(from: string) { return date }
        timestamp.formatOptions = [.withInternetDateTime]
        if let date = timestamp.date(from: string) { return date }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        day.timeZone = TimeZone(identifier: "UTC")
        return day.date(from: string)
    }

    /// The length of the calendar month that ends at `reset`: what a
    /// monthly quota's window is.
    static func monthLength(endingAt reset: Date) -> TimeInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(byAdding: .month, value: -1, to: reset) ?? reset.addingTimeInterval(-30 * 86400)
        return reset.timeIntervalSince(start)
    }
}
