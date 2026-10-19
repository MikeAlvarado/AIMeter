import Foundation
import UsageKit

/// The order accounts show in with "Order by urgency" on
/// (`Preferences.ordersByUrgency`): the one closest to a limit first, on
/// the Dashboard, in the menu bar popover, the notch island and on the
/// Watch (all drawn from `UsageModel.accounts`) and in the all-accounts
/// widget (sorted as it reads the registry). The registry keeps the
/// user's own order underneath, untouched, for when the switch goes off.
enum AccountOrder {
    /// How close an account is to a limit: its most used window's
    /// percentage, a window the provider flags critical or exceeded
    /// counting as full. Nil with no snapshot: nothing to say yet.
    static func urgency(of snapshot: UsageSnapshot?) -> Double? {
        guard let windows = snapshot?.windows, !windows.isEmpty else { return nil }
        return windows.map { window in
            window.severity == .critical || window.severity == .exceeded ? max(window.usedPct, 100) : window.usedPct
        }.max()
    }

    /// The most urgent first, those with no snapshot last; equals keep
    /// their order (the sort is stable), so a tie leaves the user's own.
    static func byUrgency<T>(_ items: [T], snapshot: (T) -> UsageSnapshot?) -> [T] {
        items.sorted { lhs, rhs in
            switch (urgency(of: snapshot(lhs)), urgency(of: snapshot(rhs))) {
            case let (l?, r?): return l > r
            case (.some, nil): return true
            default: return false
            }
        }
    }
}
