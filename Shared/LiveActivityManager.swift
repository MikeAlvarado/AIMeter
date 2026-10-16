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
        accountID: String, accountName: String, accountIcon: AccountIcon? = nil, providerID: String,
        snapshot: UsageSnapshot?, enabled: Bool, mayStart: Bool = true
    ) {
        let mine = running(accountID: accountID)

        guard let content = content(for: snapshot, providerID: providerID, enabled: enabled) else {
            for activity in mine {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }

        let pet = LiveActivityPreferences(accountID: accountID).pet
        if let current = mine.first(where: { $0.attributes.pet == pet }) {
            Task { await current.update(content) }
            // Any other is left over (a restart's old one still ending, or a
            // duplicate): one activity per account.
            for extra in mine where extra.id != current.id {
                Task { await extra.end(nil, dismissalPolicy: .immediate) }
            }
        } else if let running = mine.first {
            if mayStart {
                // Its pet was switched on or off since it started (or it
                // predates pets): only a new activity can carry the change.
                restart(
                    accountID: accountID, accountName: accountName, accountIcon: accountIcon,
                    providerID: providerID, snapshot: snapshot, enabled: enabled
                )
            } else {
                Task { await running.update(content) }
            }
        } else if mayStart {
            start(accountID: accountID, accountName: accountName, accountIcon: accountIcon, content: content)
        }
    }

    /// This account's activities still on screen (ended and dismissed ones
    /// linger in `Activity.activities` for a moment).
    private static func running(accountID: String) -> [Activity<SessionActivityAttributes>] {
        Activity<SessionActivityAttributes>.activities.filter {
            $0.attributes.accountID == accountID && $0.activityState != .ended && $0.activityState != .dismissed
        }
    }

    /// Restarts a running activity under a new nickname, icon or pet.
    /// `attributes` (the name, icon and pet among them) are fixed for an
    /// activity's lifetime, so none of these changes
    /// can ride on `update` the way every other change does: a fresh
    /// activity starts and the old one ends. Nothing to do when none is
    /// running — the next `sync` picks the new name up on its own. Called
    /// from the rename and icon actions, the pet's switch and a `sync`
    /// allowed to start one. The new one is requested first, synchronously
    /// (`Activity.request` is), so a second restart, a `sync` or an `end`
    /// that runs before the old one is gone already sees it; and when the
    /// request fails (the app in the background, which `Activity.request`
    /// refuses, or Live Activities switched off), the old one stays rather
    /// than none.
    static func restart(
        accountID: String, accountName: String, accountIcon: AccountIcon? = nil,
        providerID: String, snapshot: UsageSnapshot?, enabled: Bool
    ) {
        let old = running(accountID: accountID)
        guard !old.isEmpty else { return }
        if let content = content(for: snapshot, providerID: providerID, enabled: enabled),
           start(accountID: accountID, accountName: accountName, accountIcon: accountIcon, content: content) == nil {
            return
        }
        for activity in old {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
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

    @discardableResult
    private static func start(
        accountID: String, accountName: String, accountIcon: AccountIcon?,
        content: ActivityContent<SessionActivityAttributes.ContentState>
    ) -> Activity<SessionActivityAttributes>? {
        // The user can switch Live Activities off per app in Settings;
        // `request` would just throw, but checking makes the no-op explicit.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        let attributes = SessionActivityAttributes(
            accountID: accountID, accountName: accountName, accountIcon: accountIcon,
            pet: LiveActivityPreferences(accountID: accountID).pet
        )
        return try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }
}

/// This feature's two per-account toggles, the activity and its pet: off
/// by default, the same App-Group-backed, accountID-scoped storage
/// `NotificationPreferences` already uses.
struct LiveActivityPreferences {
    let accountID: String
    private let defaults: UserDefaults

    /// `defaults` is for the tests (a throwaway suite); the app always uses
    /// the App Group.
    init(accountID: String, defaults: UserDefaults? = nil) {
        self.accountID = accountID
        self.defaults = defaults ?? UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    var enabled: Bool {
        get { defaults.bool(forKey: "liveActivity.enabled.\(accountID)") }
        nonmutating set { defaults.set(newValue, forKey: "liveActivity.enabled.\(accountID)") }
    }

    /// "Show a pet": the account's pet beside its countdown, getting
    /// nervous as the session nears its limit (`SessionPetMood`).
    var showsPet: Bool {
        get { defaults.bool(forKey: "liveActivity.pet.\(accountID)") }
        nonmutating set { defaults.set(newValue, forKey: "liveActivity.pet.\(accountID)") }
    }

    /// The pet a new activity carries (`SessionActivityAttributes.pet`).
    var pet: SessionActivityAttributes.Pet? {
        guard showsPet else { return nil }
        let pet = SessionPet(accountID: accountID)
        return .init(creature: pet.creature.rawValue, palette: pet.palette.rawValue, accessory: pet.accessory.rawValue)
    }

    /// On disconnect, so the keys don't outlive the account.
    func clear() {
        defaults.removeObject(forKey: "liveActivity.enabled.\(accountID)")
        defaults.removeObject(forKey: "liveActivity.pet.\(accountID)")
    }
}
#endif
