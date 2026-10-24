#if os(macOS)
import Foundation
import UsageKit
import UserNotifications

/// The "needs you" notification of `ClaudeSessionMonitor`: which sessions
/// started or stopped waiting for permission between two looks, the notice
/// itself, and taking it back. Its members are internal rather than
/// private only because the monitor, in its own file, calls them.
extension ClaudeSessionMonitor {
    /// The sessions waiting for permission now that weren't a moment ago.
    static func newlyAsking(before: [String: ClaudeCodeSessionActivity], after: [String: ClaudeCodeSessionActivity]) -> [ClaudeCodeSessionActivity] {
        after.values
            .filter { $0.isAskingPermission && !(before[$0.id]?.isAskingPermission ?? false) }
            .sorted { $0.id < $1.id }
    }

    /// The ids of the sessions that were waiting for permission and no
    /// longer are: answered, interrupted, finished or ended.
    static func noLongerAsking(before: [String: ClaudeCodeSessionActivity], after: [String: ClaudeCodeSessionActivity]) -> [String] {
        before.values
            .filter { $0.isAskingPermission && !(after[$0.id]?.isAskingPermission ?? false) }
            .map(\.id)
            .sorted()
    }

    func announce(_ session: ClaudeCodeSessionActivity) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(session.name) needs you")
        content.body = String(localized: "Claude Code is asking for your permission.")
        let request = UNNotificationRequest(identifier: Self.notificationPrefix + session.id, content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    /// Removes this feature's delivered notifications whose identifier
    /// `matches` says so.
    static func withdrawDelivered(_ matches: @escaping @Sendable (String) -> Bool) async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(notificationPrefix) && matches($0) }
        if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
    }
}

extension ClaudeCodeSessionActivity {
    var isAskingPermission: Bool {
        if case .needsPermission = state { return true }
        return false
    }
}
#endif
