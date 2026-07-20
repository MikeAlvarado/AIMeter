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
    /// Spending cap state, when the provider reports one.
    public var spend: SpendStatus?
    /// Extra-usage credit pool state, when the provider reports one.
    public var extraUsage: ExtraUsageStatus?

    public init(
        providerID: String,
        planName: String? = nil,
        fetchedAt: Date = Date(),
        windows: [UsageWindow],
        spend: SpendStatus? = nil,
        extraUsage: ExtraUsageStatus? = nil
    ) {
        self.providerID = providerID
        self.planName = planName
        self.fetchedAt = fetchedAt
        self.windows = windows
        self.spend = spend
        self.extraUsage = extraUsage
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

    /// Providers omit `resetsAt` for windows with no usage yet, but weekly
    /// windows roll over on a fixed anchor: the previously reported date
    /// advanced by whole periods is still the true boundary. Fills those
    /// gaps from the last snapshot so reset lines never blink out after a
    /// rollover. Session windows only carry a still-future date — an idle
    /// session genuinely has no reset.
    public func fillingMissingResets(from previous: UsageSnapshot?, now: Date = Date()) -> UsageSnapshot {
        guard let previous else { return self }
        var updated = self
        updated.windows = windows.map { window in
            guard window.resetsAt == nil,
                  let old = previous.windows.first(where: { $0.kind == window.kind })?.resetsAt
            else { return window }
            var filled = window
            filled.resetsAt = Self.advance(old, by: window.kind.nominalPeriod, until: now)
            return filled
        }
        return updated
    }

    private static func advance(_ date: Date, by period: TimeInterval?, until now: Date) -> Date? {
        if date > now { return date }
        guard let period, period > 0 else { return nil }
        var next = date
        while next <= now {
            next += period
        }
        return next
    }
}

extension UsageWindow.Kind {
    /// The kind's nominal rollover period, when the kind itself defines
    /// one: weekly windows repeat every 7 days. Sessions start on first
    /// use, so they have no fixed anchor.
    var nominalPeriod: TimeInterval? {
        switch self {
        case .weekly, .modelSpecific:
            return 7 * 86400
        case .session:
            return nil
        }
    }
}
