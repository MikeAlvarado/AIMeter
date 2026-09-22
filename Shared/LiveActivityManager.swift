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
    /// toggle is off and nothing is running. `mayStart` is false on code
    /// paths where ActivityKit refuses `Activity.request` (the
    /// `BGAppRefreshTask`); an update to one already running is fine
    /// there. Only ever called from the app process — the widget extension
    /// sees an empty `Activity.activities` and can neither start nor
    /// update one, which is why `WidgetRefresher` doesn't call this.
    static func sync(
        accountID: String, accountName: String, providerID: String,
        snapshot: UsageSnapshot?, enabled: Bool, mayStart: Bool = true
    ) {
        let running = Activity<SessionActivityAttributes>.activities.first { $0.attributes.accountID == accountID }

        guard let content = content(for: snapshot, providerID: providerID, enabled: enabled) else {
            guard let running else { return }
            Task { await running.end(nil, dismissalPolicy: .immediate) }
            return
        }

        if let running {
            Task { await running.update(content) }
        } else if mayStart {
            start(accountID: accountID, accountName: accountName, content: content)
        }
    }

    /// Restarts a running activity under a new nickname. `attributes` (the
    /// name among them) are fixed for an activity's lifetime, so a rename
    /// can't ride on `update` the way every other change does: the old
    /// activity ends and a fresh one starts in its place. Nothing to do
    /// when none is running — the next `sync` picks the new name up on its
    /// own. Called from the rename action only, so the app is in the
    /// foreground, which `Activity.request` requires.
    static func rename(
        accountID: String, accountName: String, providerID: String, snapshot: UsageSnapshot?, enabled: Bool
    ) {
        let running = Activity<SessionActivityAttributes>.activities.filter { $0.attributes.accountID == accountID }
        guard !running.isEmpty else { return }
        let content = content(for: snapshot, providerID: providerID, enabled: enabled)
        Task {
            for activity in running {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            guard let content else { return }
            start(accountID: accountID, accountName: accountName, content: content)
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

    /// What a live session shows, or nil when there's nothing to show
    /// (toggle off, no session window, an idle one, or one already past
    /// its reset) — which `sync` reads as "end whatever is running".
    private static func content(
        for snapshot: UsageSnapshot?, providerID: String, enabled: Bool
    ) -> ActivityContent<SessionActivityAttributes.ContentState>? {
        guard enabled,
              let window = snapshot?.sessionWindow,
              window.usedPct > 0,
              let resetsAt = window.resetsAt,
              resetsAt > Date()
        else { return nil }
        return ActivityContent(
            state: SessionActivityAttributes.ContentState(
                usedPct: window.usedPct,
                resetsAt: resetsAt,
                isPeak: ClaudePeakStatus.forProvider(providerID).isPeak,
                severity: window.severity
            ),
            staleDate: resetsAt
        )
    }

    private static func start(
        accountID: String, accountName: String, content: ActivityContent<SessionActivityAttributes.ContentState>
    ) {
        // The user can switch Live Activities off per app in Settings;
        // `request` would just throw, but checking makes the no-op explicit.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = SessionActivityAttributes(accountID: accountID, accountName: accountName)
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
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

    /// On disconnect, so the key doesn't outlive the account.
    func clear() {
        defaults.removeObject(forKey: "liveActivity.enabled.\(accountID)")
    }
}
#endif
