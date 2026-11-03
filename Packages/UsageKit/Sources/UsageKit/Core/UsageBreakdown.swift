import Foundation

/// Where a period's usage went, by the app or surface that spent it
/// ("Claude Code" 97 %, "Cowork" 3 %), as the provider itself divides it.
/// Display-only: the names come from the provider, as model names do,
/// and the shares are of what was used, not of the limit.
public struct UsageBreakdown: Codable, Hashable, Sendable {
    public struct Share: Codable, Hashable, Sendable {
        /// The provider's stable id for the surface ("claude_code").
        public var key: String
        /// The name the provider shows for it ("Claude Code").
        public var name: String
        /// Its share of the period's usage, 0–100.
        public var percent: Double

        public init(key: String, name: String, percent: Double) {
            self.key = key
            self.name = name
            self.percent = percent
        }
    }

    /// In the provider's order.
    public var shares: [Share]
    /// When the period this divides began.
    public var periodStart: Date?

    public init(shares: [Share], periodStart: Date? = nil) {
        self.shares = shares
        self.periodStart = periodStart
    }

    /// Worth drawing: at least one surface spent something.
    public var hasUsage: Bool {
        shares.contains { $0.percent > 0 }
    }
}
