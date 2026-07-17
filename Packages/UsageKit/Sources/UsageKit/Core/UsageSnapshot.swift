import Foundation

/// The full usage state of one provider account at a point in time.
public struct UsageSnapshot: Codable, Hashable, Sendable {
    /// Stable provider identifier, e.g. "claude". Matches `UsageProvider.id`.
    public var providerID: String
    /// Human-readable plan name reported by the provider, e.g. "pro", "max".
    public var planName: String?
    /// When this snapshot was fetched. Widgets show this as "last updated"
    /// when displaying stale data after a failed refresh.
    public var fetchedAt: Date
    public var windows: [UsageWindow]

    public init(
        providerID: String,
        planName: String? = nil,
        fetchedAt: Date = Date(),
        windows: [UsageWindow]
    ) {
        self.providerID = providerID
        self.planName = planName
        self.fetchedAt = fetchedAt
        self.windows = windows
    }

    public var sessionWindow: UsageWindow? {
        windows.first { $0.kind == .session }
    }

    public var weeklyWindow: UsageWindow? {
        windows.first { $0.kind == .weekly }
    }

    public var modelWindows: [UsageWindow] {
        windows.filter {
            if case .modelSpecific = $0.kind { return true }
            return false
        }
    }
}
