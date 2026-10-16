import Foundation
import UserNotifications
import UsageKit

/// Run-out warnings: one per window projected to run out early, a lead
/// time before it does, and once for that window.
extension NotificationScheduler {
    /// How long before the projected exhaustion to fire the warning, so
    /// it's actionable rather than after the fact.
    static let runOutLead: TimeInterval = 20 * 60
    /// The `userInfo` key a warning carries its window's reset under.
    static let runOutResetKey = "resetsAt"

    // MARK: - Run-out warnings (per-window, ahead of a projected early exhaustion)

    /// Schedules one warning per window projected to run out early. The
    /// caller supplies projections (recent-rate when history exists, else
    /// average-rate). Rescheduled every fetch, so a later fetch showing
    /// deceleration removes a warning that no longer applies. A window
    /// already warned about isn't warned about again: inside the lead
    /// time every fetch would otherwise schedule another a minute out.
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
        let delivered = await center.deliveredNotifications().map {
            (identifier: $0.request.identifier, resetsAt: $0.request.content.userInfo[runOutResetKey] as? TimeInterval)
        }

        for (kind, projection) in projections {
            guard projection.runsOutEarly else { continue }
            let identifier = runOutPrefix + accountID + "." + kind.storageKey
            guard !warnedAlready(delivered, identifier: identifier, resetsAt: projection.resetsAt) else { continue }

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
            content.userInfo = [runOutResetKey: projection.resetsAt.timeIntervalSince1970]

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: triggerComponents(at: fireDate), repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// Whether this window's warning is already in Notification Center:
    /// the same identifier with the same reset, give or take a minute (two
    /// windows of one kind are hours apart; one window's timestamp isn't
    /// always to the microsecond the same).
    static func warnedAlready(
        _ delivered: [(identifier: String, resetsAt: TimeInterval?)],
        identifier: String,
        resetsAt: Date
    ) -> Bool {
        delivered.contains {
            $0.identifier == identifier
                && $0.resetsAt.map { abs($0 - resetsAt.timeIntervalSince1970) < 60 } == true
        }
    }
}
