import Foundation
import UserNotifications
import UsageKit

/// Per-window notification toggles, stored in the App Group so future
/// surfaces (e.g. widget configuration) can read them too. Off by default.
struct NotificationPreferences {
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard

    func isEnabled(for kind: UsageWindow.Kind) -> Bool {
        defaults.bool(forKey: key(for: kind))
    }

    func setEnabled(_ enabled: Bool, for kind: UsageWindow.Kind) {
        defaults.set(enabled, forKey: key(for: kind))
    }

    private func key(for kind: UsageWindow.Kind) -> String {
        "notify.\(kind.storageKey)"
    }
}

/// Schedules one local notification per enabled window at its resetsAt.
/// Rescheduled from scratch after every successful fetch, so reset times
/// track what the endpoint currently reports.
enum NotificationScheduler {
    private static let identifierPrefix = "reset."

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func reschedule(for snapshot: UsageSnapshot?, preferences: NotificationPreferences) async {
        let center = UNUserNotificationCenter.current()

        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard let snapshot else { return }

        for window in snapshot.windows {
            guard preferences.isEnabled(for: window.kind),
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
                identifier: identifierPrefix + window.kind.storageKey,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
