import Foundation

/// A source of AI subscription usage data. Implementations own all details
/// of their endpoint and authentication; callers only see `UsageSnapshot`.
public protocol UsageProvider: Sendable {
    /// Stable identifier used as the storage key for snapshots, e.g. "claude".
    var id: String { get }
    /// Name shown in UI, e.g. "Claude".
    var displayName: String { get }

    func fetchUsage() async throws -> UsageSnapshot
}
