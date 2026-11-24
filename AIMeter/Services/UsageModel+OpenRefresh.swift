import Foundation

/// Opening the notch island or the menu bar popover is the user asking
/// for the figures, so it refreshes them, the way the Refresh button
/// would, with a floor of `openRefreshMinimumInterval` between two: opening
/// and closing over and over never sends more than one sweep in that time.
/// An account fetched within the floor is skipped (`refreshAllIfStale`), and
/// one already fetching isn't fetched twice (`fetch(accountID:)`); the floor
/// itself is what keeps a failing account, whose snapshot never gets newer,
/// from being asked again on every open.
extension UsageModel {
    nonisolated static let openRefreshMinimumInterval: TimeInterval = 15

    /// Pure throttle rule, so the tests can pin it without a clock.
    nonisolated static func isOpenRefreshDue(
        lastRefreshed: Date?,
        now: Date,
        minimumInterval: TimeInterval = openRefreshMinimumInterval
    ) -> Bool {
        guard let lastRefreshed else { return true }
        return now.timeIntervalSince(lastRefreshed) >= minimumInterval
    }

    /// Called when the island opens or the popover appears. Returns
    /// whether it refreshed (the tests' handle); the refresh itself runs in
    /// a task of its own, so closing again doesn't cancel it.
    @discardableResult
    func refreshOnOpen(now: Date = Date()) -> Bool {
        guard !isDemoMode, !accounts.isEmpty,
              Self.isOpenRefreshDue(lastRefreshed: lastOpenRefresh, now: now) else { return false }
        lastOpenRefresh = now
        Task { await refreshAllIfStale(maxAge: Self.openRefreshMinimumInterval) }
        return true
    }
}
