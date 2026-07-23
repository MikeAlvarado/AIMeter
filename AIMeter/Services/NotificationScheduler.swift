import Foundation
import UserNotifications
import UsageKit

/// Notification toggles, stored in the App Group so future surfaces (e.g.
/// widget configuration) can read them too. All off by default. Per-window
/// "reset" toggles are the free baseline; the two "smart" toggles
/// (run-out warnings, early-reset alerts) are global across windows.
struct NotificationPreferences {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard

    func isEnabled(for providerID: String, kind: UsageWindow.Kind) -> Bool {
        defaults.bool(forKey: key(for: providerID, kind: kind))
    }

    func setEnabled(_ enabled: Bool, for providerID: String, kind: UsageWindow.Kind) {
        defaults.set(enabled, forKey: key(for: providerID, kind: kind))
    }

    /// "At this rate, [window] runs out before it resets" warnings.
    var runOutWarningsEnabled: Bool {
        get { defaults.bool(forKey: "notify.runout") }
        nonmutating set { defaults.set(newValue, forKey: "notify.runout") }
    }

    /// "[window] refilled early" alerts.
    var earlyResetAlertsEnabled: Bool {
        get { defaults.bool(forKey: "notify.earlyReset") }
        nonmutating set { defaults.set(newValue, forKey: "notify.earlyReset") }
    }

    /// "[window] nearing its limit" warnings, fired when used% crosses
    /// `nearLimitThreshold` upward.
    var nearLimitEnabled: Bool {
        get { defaults.bool(forKey: "notify.nearLimit") }
        nonmutating set { defaults.set(newValue, forKey: "notify.nearLimit") }
    }

    /// User-set used% at which the near-limit warning fires. Default 80,
    /// kept below the limit-reached threshold so the two don't collide.
    var nearLimitThreshold: Double {
        get {
            let stored = defaults.double(forKey: "notify.nearLimitThreshold")
            return stored == 0 ? 80 : stored
        }
        nonmutating set {
            defaults.set(min(95, max(50, newValue)), forKey: "notify.nearLimitThreshold")
        }
    }

    /// "[window] limit reached" alerts (message adapts to whether the
    /// account has credits).
    var limitReachedEnabled: Bool {
        get { defaults.bool(forKey: "notify.limitReached") }
        nonmutating set { defaults.set(newValue, forKey: "notify.limitReached") }
    }

    /// Provider-scoped: two providers reporting the same `kind` (e.g. both
    /// `.session`) must not share a toggle.
    private func key(for providerID: String, kind: UsageWindow.Kind) -> String {
        "notify.\(providerID).\(kind.storageKey)"
    }
}

/// Schedules the local notifications, all rescheduled from scratch after
/// every successful fetch so they track what the endpoint currently
/// reports. Three independent families, each keyed by its own identifier
/// prefix so they never clobber one another:
/// - `reset.` — per-window, fires at the window's `resetsAt` ("back to full").
/// - `runout.` — per-window run-out warnings, fired ahead of a projected
///   early exhaustion (recent-rate projection supplied by the caller).
/// - `earlyreset.` — immediate alerts when a window refilled early.
enum NotificationScheduler {
    private static let identifierPrefix = "reset."
    private static let runOutPrefix = "runout."
    private static let earlyResetPrefix = "earlyreset."
    private static let nearLimitPrefix = "nearlimit."
    private static let limitReachedPrefix = "limitreached."
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
    private static func canDeliver() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    // MARK: - Reset notifications (per-window, at resetsAt)

    /// `providerID` is explicit rather than read from `snapshot` — the
    /// snapshot can be nil (e.g. toggling a preference before any fetch),
    /// and the remove-then-readd below must still only touch this
    /// provider's own pending requests, not every provider's.
    static func rescheduleResets(for snapshot: UsageSnapshot?, providerID: String, preferences: NotificationPreferences) async {
        let center = UNUserNotificationCenter.current()
        await removePending(withPrefix: identifierPrefix + providerID + ".", from: center)

        guard let snapshot, await canDeliver() else { return }

        for window in snapshot.windows {
            guard preferences.isEnabled(for: providerID, kind: window.kind),
                  let resetsAt = window.resetsAt,
                  resetsAt > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(window.kind.displayName) limit reset")
            content.body = String(localized: "Your \(window.kind.displayName) usage window has reset. Full capacity available.")
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: resetsAt
            )
            let request = UNNotificationRequest(
                identifier: identifierPrefix + providerID + "." + window.kind.storageKey,
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
        providerID: String,
        preferences: NotificationPreferences,
        now: Date = Date()
    ) async {
        let center = UNUserNotificationCenter.current()
        await removePending(withPrefix: runOutPrefix + providerID + ".", from: center)

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
            content.title = String(localized: "\(kind.displayName) running low")
            content.body = String(localized: "At this rate it runs out about \(earlyBy) before it resets.")
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let request = UNNotificationRequest(
                identifier: runOutPrefix + providerID + "." + kind.storageKey,
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
    static func notifyEarlyResets(_ kinds: [UsageWindow.Kind], providerID: String, preferences: NotificationPreferences) async {
        guard preferences.earlyResetAlertsEnabled, !kinds.isEmpty, await canDeliver() else { return }
        let center = UNUserNotificationCenter.current()

        for kind in kinds {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(kind.displayName) refilled early")
            content.body = String(localized: "Your \(kind.displayName) limit reset ahead of schedule — full capacity available.")
            content.sound = .default

            // A unique id per event so repeated early resets each notify.
            let request = UNNotificationRequest(
                identifier: earlyResetPrefix + providerID + "." + kind.storageKey + "." + String(Int(Date().timeIntervalSince1970)),
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    // MARK: - Near-limit warnings (immediate, on threshold crossing)

    /// Posts an immediate warning for each window that just crossed the
    /// near-limit threshold. `current` supplies the real used% for the copy.
    static func notifyNearLimit(_ kinds: [UsageWindow.Kind], in current: UsageSnapshot, preferences: NotificationPreferences) async {
        guard preferences.nearLimitEnabled, !kinds.isEmpty, await canDeliver() else { return }
        let center = UNUserNotificationCenter.current()

        for kind in kinds {
            let used = current.windows.first { $0.kind == kind }?.usedPct ?? 0
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(kind.displayName) nearing its limit")
            content.body = String(localized: "You're at \(Int(used))% of this window.")
            content.sound = .default
            await add(content, prefix: nearLimitPrefix, providerID: current.providerID, kind: kind, to: center)
        }
    }

    // MARK: - Limit-reached alerts (immediate, on hitting ~100%)

    /// Posts an immediate alert for each window that just hit its limit. The
    /// body adapts: when the account has credits enabled, continuing draws
    /// on them; otherwise the window is blocked until it resets.
    static func notifyLimitReached(_ kinds: [UsageWindow.Kind], in current: UsageSnapshot, preferences: NotificationPreferences) async {
        guard preferences.limitReachedEnabled, !kinds.isEmpty, await canDeliver() else { return }
        let center = UNUserNotificationCenter.current()
        let hasCredits = current.spend?.enabled ?? false

        for kind in kinds {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(kind.displayName) limit reached")
            content.body = hasCredits
                ? String(localized: "Further usage now draws on your usage credits.")
                : String(localized: "You're blocked on this limit until it resets.")
            content.sound = .default
            await add(content, prefix: limitReachedPrefix, providerID: current.providerID, kind: kind, to: center)
        }
    }

    /// Adds an immediate (nil-trigger) notification with a unique per-event
    /// id, so repeated crossings each deliver rather than replacing.
    private static func add(_ content: UNMutableNotificationContent, prefix: String, providerID: String, kind: UsageWindow.Kind, to center: UNUserNotificationCenter) async {
        let request = UNNotificationRequest(
            identifier: prefix + providerID + "." + kind.storageKey + "." + String(Int(Date().timeIntervalSince1970)),
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private static func removePending(withPrefix prefix: String, from center: UNUserNotificationCenter) async {
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }
}
