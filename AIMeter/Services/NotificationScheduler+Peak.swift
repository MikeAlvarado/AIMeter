import Foundation
import UserNotifications
import UsageKit

/// The one account-independent family, kept apart from the per-account
/// ones: it depends on a fixed schedule, never on a fetch.
extension NotificationScheduler {
    // MARK: - Peak-hours alerts (recurring, from a fixed schedule)

    /// Schedules "Peak hours started"/"Peak hours ended" alerts from
    /// Claude's documented weekday schedule — 10 recurring calendar
    /// triggers (one weekday × start/end pair each), pinned to the
    /// schedule's own named timezone so DST is handled the same way
    /// `PeakCalculator` handles it: by asking the zone, never a fixed
    /// offset. Deliberately *not* part of the "reschedule every fetch"
    /// convention the other families follow — this schedule never depends
    /// on a fetched snapshot, so it only needs (re)scheduling once at
    /// launch and whenever the toggle changes; call sites should not add
    /// it to the per-fetch reschedule sweep in `RefreshService`.
    static func reschedulePeakNotifications(
        schedule: PeakCalculator.Schedule? = ClaudePeakSchedule.current,
        preferences: NotificationPreferences
    ) async {
        let center = UNUserNotificationCenter.current()
        await removePending(withPrefix: peakPrefix, from: center)

        // No schedule in force (the policy is retired — see
        // `ClaudePeakSchedule`): the removal above is the whole job, so an
        // install upgrading with the toggle on stops getting alerts for a
        // window that no longer exists.
        guard let schedule, preferences.peakEnabled, await canDeliver() else { return }
        guard let timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) else { return }

        for weekday in schedule.weekdays {
            await addPeakTrigger(
                weekday: weekday, hour: schedule.startHour, timeZone: timeZone,
                title: String(localized: "Peak hours started"),
                body: String(localized: "Claude session usage may burn faster right now."),
                suffix: "start",
                to: center
            )
            await addPeakTrigger(
                weekday: weekday, hour: schedule.endHour, timeZone: timeZone,
                title: String(localized: "Peak hours ended"),
                body: String(localized: "Claude session usage is back to its normal rate."),
                suffix: "end",
                to: center
            )
        }
    }

    private static func addPeakTrigger(
        weekday: Int,
        hour: Int,
        timeZone: TimeZone,
        title: String,
        body: String,
        suffix: String,
        to center: UNUserNotificationCenter
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = DateComponents()
        components.timeZone = timeZone
        components.weekday = weekday
        components.hour = hour
        components.minute = 0

        let request = UNNotificationRequest(
            identifier: "\(peakPrefix)\(weekday).\(suffix)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await center.add(request)
    }
}
