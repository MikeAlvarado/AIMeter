import Foundation

/// Money-based usage state a provider may report alongside its rate
/// windows: a spending cap on the account. Amounts are in major currency
/// units (e.g. 10.76 USD).
public struct SpendStatus: Codable, Hashable, Sendable {
    public var enabled: Bool
    /// Percentage of the spend limit already used, 0–100.
    public var percent: Double?
    public var severity: UsageWindow.Severity?
    public var usedAmount: Double?
    public var limitAmount: Double?
    /// ISO 4217 code, e.g. "USD".
    public var currency: String?

    public init(
        enabled: Bool,
        percent: Double? = nil,
        severity: UsageWindow.Severity? = nil,
        usedAmount: Double? = nil,
        limitAmount: Double? = nil,
        currency: String? = nil
    ) {
        self.enabled = enabled
        self.percent = percent
        self.severity = severity
        self.usedAmount = usedAmount
        self.limitAmount = limitAmount
        self.currency = currency
    }
}

/// Overflow-credits pool some plans offer once rate windows are exhausted
/// ("extra usage"). Amounts are in major currency units.
public struct ExtraUsageStatus: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var usedCredits: Double?
    public var monthlyLimit: Double?
    /// Percentage of the monthly credit pool already used, 0–100.
    public var utilization: Double?
    public var currency: String?

    public init(
        enabled: Bool,
        usedCredits: Double? = nil,
        monthlyLimit: Double? = nil,
        utilization: Double? = nil,
        currency: String? = nil
    ) {
        self.enabled = enabled
        self.usedCredits = usedCredits
        self.monthlyLimit = monthlyLimit
        self.utilization = utilization
        self.currency = currency
    }
}
