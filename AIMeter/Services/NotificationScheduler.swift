import Foundation
import UserNotifications
import UsageKit

/// Schedules the local notifications, all rescheduled from scratch after
/// every successful fetch so they track what the endpoint currently
/// reports. Every identifier includes the triggering account's id (except
/// `peak.`, which is account-independent) so two accounts with the same
/// window kind never clobber each other's pending requests:
/// - `reset.` — per-window, fires at the window's `resetsAt` ("back to full").
/// - `runout.` — per-window run-out warnings, fired ahead of a projected
///   early exhaustion (recent-rate projection supplied by the caller).
/// - `earlyreset.` — immediate alerts when a window refilled early.
/// - `reauth.` — an immediate alert when the account's stored sign-in
///   stopped working, deduped so it fires once per breakage.
/// - `peak.` — see `NotificationScheduler+Peak.swift`.
/// The toggles themselves are `NotificationPreferences`
/// (`NotificationPreferences.swift`).
enum NotificationScheduler {
    private static let identifierPrefix = "reset."
    private static let runOutPrefix = "runout."
    private static let earlyResetPrefix = "earlyreset."
    private static let nearLimitPrefix = "nearlimit."
    private static let limitReachedPrefix = "limitreached."
    static let peakPrefix = "peak."
    private static let reauthPrefix = "reauth."
    /// How long before the projected exhaustion to fire the warning, so
    /// it's actionable rather than after the fact.
    private static let runOutLead: TimeInterval = 20 * 60

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// True when notifications can actually be delivered, prompting the
    /// first time. A previous denial returns false without re-prompting
    /// (the system would ignore the request anyway).
    static func ensureAuthorization() async -> Bool {
        switch await authorizationStatus() {
        case .notDetermined:
            return await requestAuthorization()
        case .denied:
            return false
        default:
            return true
        }
    }

    /// True when iOS will actually deliver requests we add now.
    static func canDeliver() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    // MARK: - Reset notifications (per-window, at resetsAt)

    static func rescheduleResets(
        for snapshot: UsageSnapshot?,
        accountID: String,
        accountLabel: String? = nil,
        preferences: NotificationPreferences
    ) async {
        let center = UNUserNotificationCenter.current()
        await removePending(withPrefix: identifierPrefix + accountID + ".", from: center)

        guard let snapshot, await canDeliver() else { return }

        for window in snapshot.windows {
            guard preferences.isEnabled(for: window.kind),
                  let resetsAt = window.resetsAt,
                  resetsAt > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = labeled(String(localized: "\(window.kind.displayName) limit reset"), accountLabel)
            content.body = String(localized: "Your \(window.kind.displayName) usage window has reset. Full capacity available.")
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: resetsAt
            )
            let request = UNNotificationRequest(
                identifier: identifierPrefix + accountID + "." + window.kind.storageKey,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    // MARK: - Run-out warnings (per-window, ahead of a projected early exhaustion)

    /// Schedules one warning per window projected to run out early. The
    /// caller supplies projections (recent-rate when history exists, else
    /// average-rate). Rescheduled every fetch, so a later fetch showing
    /// deceleration removes a warning that no longer applies.
    static func rescheduleRunOuts(
        _ projections: [UsageWindow.Kind: RunOutProjection],
        accountID: String,
        accountLabel: String? = nil,
        preferences: NotificationPreferences,
        now: Date = Date()
    ) async {
        let center = UNUserNotificationCenter.current()
        await removePending(withPrefix: runOutPrefix + accountID + ".", from: center)

        guard preferences.runOutWarningsEnabled, await canDeliver() else { return }

        for (kind, projection) in projections {
            guard projection.runsOutEarly else { continue }

            // Fire a lead time before the projected exhaustion, but never in
            // the past and never after the window has already reset.
            var fireDate = projection.projectedExhaustion.addingTimeInterval(-runOutLead)
            if fireDate <= now { fireDate = now.addingTimeInterval(60) }
            guard fireDate < projection.resetsAt else { continue }

            let earlyBy = UsageFormatting.relativeString(from: projection.projectedExhaustion, to: projection.resetsAt)
            let content = UNMutableNotificationContent()
            content.title = labeled(String(localized: "\(kind.displayName) running low"), accountLabel)
            content.body = String(localized: "At this rate it runs out about \(earlyBy) before it resets.")
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let request = UNNotificationRequest(
                identifier: runOutPrefix + accountID + "." + kind.storageKey,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    // MARK: - Early-reset alerts (immediate)

    /// Posts an immediate alert for each window that refilled before its
    /// scheduled reset. Not scheduled — the event already happened — so it
    /// delivers right away (nil trigger).
    static func notifyEarlyResets(
        _ kinds: [UsageWindow.Kind],
        accountID: String,
        accountLabel: String? = nil,
        preferences: NotificationPreferences
    ) async {
        guard preferences.earlyResetAlertsEnabled, !kinds.isEmpty, await canDeliver() else { return }
        let center = UNUserNotificationCenter.current()

        for kind in kinds {
            let content = UNMutableNotificationContent()
            content.title = labeled(String(localized: "\(kind.displayName) refilled early"), accountLabel)
            content.body = String(localized: "Your \(kind.displayName) limit reset ahead of schedule — full capacity available.")
            content.sound = .default

            // A unique id per event so repeated early resets each notify.
            let request = UNNotificationRequest(
                identifier: earlyResetPrefix + accountID + "." + kind.storageKey + "." + String(Int(Date().timeIntervalSince1970)),
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    // MARK: - Near-limit warnings (immediate, on threshold crossing)

    /// Posts an immediate warning for each window that just crossed the
    /// near-limit threshold. `current` supplies the real used% for the copy.
    static func notifyNearLimit(
        _ kinds: [UsageWindow.Kind],
        in current: UsageSnapshot,
        accountID: String,
        accountLabel: String? = nil,
        preferences: NotificationPreferences
    ) async {
        guard preferences.nearLimitEnabled, !kinds.isEmpty, await canDeliver() else { return }
        let center = UNUserNotificationCenter.current()

        for kind in kinds {
            let used = current.windows.first { $0.kind == kind }?.usedPct ?? 0
            let content = UNMutableNotificationContent()
            content.title = labeled(String(localized: "\(kind.displayName) nearing its limit"), accountLabel)
            content.body = String(localized: "You're at \(Int(used))% of this window.")
            content.sound = .default
            await add(content, prefix: nearLimitPrefix, accountID: accountID, kind: kind, to: center)
        }
    }

    // MARK: - Limit-reached alerts (immediate, on hitting ~100%)

    /// Posts an immediate alert for each window that just hit its limit. The
    /// body adapts: when the account has credits enabled, continuing draws
    /// on them; otherwise the window is blocked until it resets.
    static func notifyLimitReached(
        _ kinds: [UsageWindow.Kind],
        in current: UsageSnapshot,
        accountID: String,
        accountLabel: String? = nil,
        preferences: NotificationPreferences
    ) async {
        guard preferences.limitReachedEnabled, !kinds.isEmpty, await canDeliver() else { return }
        let center = UNUserNotificationCenter.current()
        let hasCredits = current.spend?.enabled ?? false

        for kind in kinds {
            let content = UNMutableNotificationContent()
            content.title = labeled(String(localized: "\(kind.displayName) limit reached"), accountLabel)
            content.body = hasCredits
                ? String(localized: "Further usage now draws on your usage credits.")
                : String(localized: "You're blocked on this limit until it resets.")
            content.sound = .default
            await add(content, prefix: limitReachedPrefix, accountID: accountID, kind: kind, to: center)
        }
    }

    /// Prefixes a notification title with the account's nickname — only
    /// when the caller supplied one, which `RefreshService` only does once
    /// more than one account is connected, so a single-account install's
    /// notifications read exactly as they always have.
    private static func labeled(_ title: String, _ accountLabel: String?) -> String {
        guard let accountLabel else { return title }
        return "\(accountLabel) — \(title)"
    }

    // MARK: - Sign-in alerts (immediate, once per breakage)

    /// Posts an immediate alert when an account's stored credentials stop
    /// working. Not scheduled — like the other detection-based families,
    /// the event has already happened by the time we know about it.
    ///
    /// The dedupe is what makes this liveable: every refresh from here on
    /// fails the same way (the credentials can't heal themselves), so
    /// without `reauthAlertDelivered` the user would get one notification
    /// per refresh cycle, forever. A fixed identifier per account also
    /// means a second delivery would merely replace the first in
    /// Notification Center rather than stack.
    static func notifyReauthenticationNeeded(
        accountID: String,
        accountLabel: String? = nil,
        preferences: NotificationPreferences
    ) async {
        guard preferences.reauthAlertsEnabled,
              !preferences.reauthAlertDelivered,
              await canDeliver() else { return }

        let content = UNMutableNotificationContent()
        content.title = labeled(String(localized: "Sign-in expired"), accountLabel)
        content.body = String(localized: "Claude rejected AIMeter's saved sign-in. Open AIMeter and sign in again to keep tracking your usage.")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: reauthPrefix + accountID,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            // Only a delivery arms the dedupe: marking it after a failed
            // `add` would silence the alert for good without it ever
            // having been shown.
            preferences.reauthAlertDelivered = true
        } catch {}
    }

    /// Everything this account has pending or delivered, on disconnect.
    /// Scheduled families are matched by their `<prefix><accountID>.` id
    /// shape; the immediate ones append a kind and timestamp after the
    /// same stem, and `reauth.` is the bare stem.
    static func removeAll(accountID: String) async {
        let center = UNUserNotificationCenter.current()
        let stems = [identifierPrefix, runOutPrefix, earlyResetPrefix, nearLimitPrefix, limitReachedPrefix]
            .map { $0 + accountID + "." } + [reauthPrefix + accountID]
        let matches: (String) -> Bool = { id in stems.contains { id.hasPrefix($0) } }
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter(matches)
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter(matches)
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    /// Re-arms the alert after a successful refresh (or a reconnect) and
    /// clears the delivered one from Notification Center — once the account
    /// is working again, an alert telling the user to sign in is worse than
    /// no alert at all.
    static func clearReauthenticationAlert(accountID: String, preferences: NotificationPreferences) {
        guard preferences.reauthAlertDelivered else { return }
        preferences.reauthAlertDelivered = false
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [reauthPrefix + accountID])
    }

    /// Adds an immediate (nil-trigger) notification with a unique per-event
    /// id, so repeated crossings each deliver rather than replacing.
    private static func add(
        _ content: UNMutableNotificationContent,
        prefix: String,
        accountID: String,
        kind: UsageWindow.Kind,
        to center: UNUserNotificationCenter
    ) async {
        let request = UNNotificationRequest(
            identifier: prefix + accountID + "." + kind.storageKey + "." + String(Int(Date().timeIntervalSince1970)),
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    static func removePending(withPrefix prefix: String, from center: UNUserNotificationCenter) async {
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }
}
