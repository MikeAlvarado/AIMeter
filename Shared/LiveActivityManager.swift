import Foundation
import UsageKit
#if os(iOS)
import ActivityKit

/// Starts, updates, and ends the Session-window Live Activity for one
/// account. Called from `RefreshService.refresh()` after every successful
/// fetch, from the account's own toggle, and from
/// `UsageModel.disconnect(accountID:)`. See "Live Activity" in
/// `AIMeterWidgets/CLAUDE.md` for the full design — updates are
/// opportunistic (piggybacking on fetches that already happen), not
/// pushed, since this app has no server.
enum LiveActivityManager {
    /// Reconciles the running activity (if any) for this account against
    /// its current snapshot and the user's toggle. A no-op when the
    /// toggle is off and nothing is running.
    static func sync(accountID: String, accountName: String, snapshot: UsageSnapshot?, enabled: Bool) {
        let running = Activity<SessionActivityAttributes>.activities.first { $0.attributes.accountID == accountID }

        guard enabled,
              let window = snapshot?.sessionWindow,
              window.usedPct > 0,
              let resetsAt = window.resetsAt,
              resetsAt > Date()
        else {
            guard let running else { return }
            Task { await running.end(nil, dismissalPolicy: .immediate) }
            return
        }

        let content = ActivityContent(
            state: SessionActivityAttributes.ContentState(
                usedPct: window.usedPct,
                resetsAt: resetsAt,
                isPeak: ClaudePeakStatus().isPeak,
                severity: window.severity
            ),
            staleDate: resetsAt
        )

        if let running {
            Task { await running.update(content) }
        } else {
            let attributes = SessionActivityAttributes(accountID: accountID, accountName: accountName)
            _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
    }

    /// Ends any running activity for this account outright — disconnect,
    /// or the toggle turning off (both want immediate removal, not the
    /// staleness-driven wind-down `sync` uses for a naturally exhausted
    /// session).
    static func end(accountID: String) {
        Task {
            for activity in Activity<SessionActivityAttributes>.activities
            where activity.attributes.accountID == accountID {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

/// The one per-account toggle this feature has — off by default, same
/// App-Group-backed, accountID-scoped storage `NotificationPreferences`
/// already uses.
struct LiveActivityPreferences {
    let accountID: String
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard

    init(accountID: String) {
        self.accountID = accountID
    }

    var enabled: Bool {
        get { defaults.bool(forKey: "liveActivity.enabled.\(accountID)") }
        nonmutating set { defaults.set(newValue, forKey: "liveActivity.enabled.\(accountID)") }
    }
}
#endif
