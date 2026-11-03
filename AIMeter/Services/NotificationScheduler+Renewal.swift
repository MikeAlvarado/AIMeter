import Foundation
import UserNotifications
import UsageKit

/// "Remind me before it renews": a notice some days before the day of the
/// month the user says the plan is charged. No service says when it bills
/// (Claude's profile only says when the subscription began, which isn't
/// the charge day; Mike, 2026-11-03), so the day is the user's, never
/// guessed. The next two reminders are kept pending, `renewal.<accountID>.0`
/// and `.1`, rescheduled after every fetch and every change, so a month
/// without opening the app still gets its notice.
extension NotificationScheduler {
    static let renewalPrefix = "renewal."
    /// The hour of the day the reminder arrives, local time.
    nonisolated static let renewalHour = 10

    /// The next `count` renewals on `day` of the month (the month's last
    /// day when it is shorter) whose reminder, `leadDays` before at
    /// `renewalHour`, is still ahead of `now`. Pure, so the tests pin it.
    nonisolated static func nextRenewals(
        day: Int, leadDays: Int, after now: Date, count: Int = 2, calendar: Calendar = .current
    ) -> [(renewal: Date, reminder: Date)] {
        var result: [(Date, Date)] = []
        guard var month = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return [] }
        for _ in 0..<24 where result.count < count {
            if let days = calendar.range(of: .day, in: .month, for: month)?.count,
               let renewal = calendar.date(bySetting: .day, value: min(day, days), of: month),
               let leadDay = calendar.date(byAdding: .day, value: -leadDays, to: renewal),
               let reminder = calendar.date(bySettingHour: renewalHour, minute: 0, second: 0, of: leadDay),
               reminder > now {
                result.append((calendar.startOfDay(for: renewal), reminder))
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return result
    }

    static func rescheduleRenewal(accountID: String, accountLabel: String?, preferences: NotificationPreferences) async {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<2).map { renewalPrefix + accountID + ".\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard preferences.renewalEnabled, await canDeliver() else { return }
        let lead = preferences.renewalLeadDays
        for (index, next) in nextRenewals(day: preferences.renewalDay, leadDays: lead, after: Date()).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = labeled(
                lead == 1 ? String(localized: "Plan renews tomorrow") : String(localized: "Plan renews in \(lead) days"),
                accountLabel
            )
            content.body = String(localized: "It renews on \(next.renewal.formatted(.dateTime.month(.wide).day())), the day you set.")
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents(at: next.reminder), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: ids[index], content: content, trigger: trigger))
        }
    }
}
