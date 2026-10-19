import Foundation
import UsageKit

/// When a widget's timeline comes back for more, and when what it holds
/// is too old to show. Pure, so the rules are tested where the widget
/// extension can't be.
enum WidgetSchedule {
    /// How long after a window's reset the widget reloads: the fetch that
    /// reload makes on iOS must find the window refilled, and the
    /// endpoint's clock is not the device's to the second.
    static let afterReset: TimeInterval = 60

    /// The next reload: the cadence from now, or a minute after the
    /// soonest reset still ahead, whichever comes first. A session that
    /// refills at 3:00 would otherwise keep its old figure until the
    /// cadence came round, up to three hours later; one reload per reset
    /// is a few a day against WidgetKit's budget.
    static func nextReload(after now: Date, interval: TimeInterval, resets: [Date]) -> Date {
        let scheduled = now.addingTimeInterval(interval)
        guard let soonest = resets.filter({ $0 > now }).min() else { return scheduled }
        return min(scheduled, soonest.addingTimeInterval(afterReset))
    }

    /// Whether a stored snapshot is worth fetching again: older than the
    /// cadence, or overtaken by a reset. A snapshot fetched at 2:50 of a
    /// session that reset at 3:00 is ten minutes old and wrong, and the
    /// reload at 3:01 exists to replace it.
    static func isStale(_ snapshot: UsageSnapshot?, cadence: TimeInterval, now: Date) -> Bool {
        guard let snapshot else { return true }
        if now.timeIntervalSince(snapshot.fetchedAt) >= cadence { return true }
        return snapshot.windows.contains { window in
            guard let resetsAt = window.resetsAt else { return false }
            return resetsAt > snapshot.fetchedAt && resetsAt <= now
        }
    }
}
