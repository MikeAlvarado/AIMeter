import SwiftUI
import UserNotifications
import UsageKit

extension Notification.Name {
    /// The tour's last step asked to connect an account: the iOS Dashboard
    /// opens its Connect sheet (the Mac goes through `AppChrome.connect`).
    static let tourConnectRequest = Notification.Name("AIMeterTourConnectRequest")
    /// Settings asked for the tour again (iOS): `ContentView` presents it.
    static let tourShowRequest = Notification.Name("AIMeterTourShowRequest")
}

/// What each tour feature's button says and does, and whether the feature
/// is on already, when the button reads "On" and the step only continues
/// (see `Tour`). Every action is the same one Settings performs, so the
/// tour never turns anything on that Settings couldn't turn off again.
@MainActor
enum TourActions {
    /// The button's title; nil for a step that only explains.
    static func title(for feature: TourFeature) -> String? {
        switch feature {
        case .alerts: String(localized: "Allow notifications")
        case .notchIsland: String(localized: "Show in the notch")
        case .sessions: String(localized: "Install hooks")
        case .sessionNames: String(localized: "Turn on")
        case .openAtLogin: String(localized: "Open at Login")
        case .connect: String(localized: "Connect")
        case .welcome, .widgets, .colors: nil
        }
    }

    /// The label once `feature` is on: "On", or "Connected" for an account.
    static func activeLabel(for feature: TourFeature) -> String {
        feature == .connect ? String(localized: "Connected") : String(localized: "On")
    }

    /// Whether `feature`'s step or card can show here at all: Claude Code's
    /// sessions live in the notch island and need Claude Code, and
    /// installing the hooks on a Mac without it would create its folder.
    static func applies(_ feature: TourFeature, prefs: PreferencesModel) -> Bool {
        #if os(macOS)
        switch feature {
        case .sessions, .sessionNames: prefs.notchIslandEnabled && Tour.claudeCodePresent
        default: true
        }
        #else
        true
        #endif
    }

    /// Whether `feature` is on already; `notificationsAllowed` is read
    /// asynchronously by the caller (`notificationsAuthorized`). An
    /// account in demo mode counts, so the tour never offers a connection
    /// underneath the fabricated accounts (the Dashboard hides "Add
    /// account" there for the same reason).
    static func isActive(_ feature: TourFeature, model: UsageModel, prefs: PreferencesModel, notificationsAllowed: Bool) -> Bool {
        switch feature {
        case .welcome, .widgets: false
        case .colors: prefs.usageColors
        case .alerts: notificationsAllowed
        case .connect: !model.accounts.isEmpty
        #if os(macOS)
        case .notchIsland: prefs.notchIslandEnabled
        case .sessions: ClaudeSessionMonitor.shared.hooksInstalled
        // The switches count, as for the login item: what may be left is
        // macOS's permission, which the label says how to give
        // (`TourActiveLabel`), rather than a button that would prompt
        // again for a permission System Settings may show as on.
        case .sessionNames: prefs.claudeSessionsShowsName && prefs.claudeSessionsAvoidsMenus
        // Registered counts, as in Settings' switch: the app did its part,
        // and what is left is the user's approval (`TourActiveLabel`).
        case .openAtLogin: LoginItemManager().isEnabled || LoginItemManager().needsApproval
        #else
        case .notchIsland, .sessions, .sessionNames, .openAtLogin: false
        #endif
        }
    }

    /// Turns `feature` on, the way its Settings switch does: a system
    /// prompt where one is needed (notifications, Accessibility, the login
    /// item), never anything a switch couldn't undo.
    static func perform(_ feature: TourFeature, model: UsageModel, prefs: PreferencesModel) async {
        switch feature {
        case .welcome, .widgets:
            break
        case .colors:
            prefs.usageColors = true
        case .alerts:
            _ = await NotificationScheduler.ensureAuthorization()
            await model.refreshNotificationAuthorization()
        case .connect:
            #if os(macOS)
            AppChrome.connect(.add)
            #else
            NotificationCenter.default.post(name: .tourConnectRequest, object: nil)
            #endif
        #if os(macOS)
        case .notchIsland:
            prefs.setNotchIsland(enabled: true)
            AppChrome.setNotchIsland(enabled: true)
        case .sessions:
            ClaudeSessionMonitor.shared.installHooks()
        case .sessionNames:
            prefs.claudeSessionsShowsName = true
            prefs.claudeSessionsAvoidsMenus = true
            AccessibilityAccess.request(prefs: prefs)
        case .openAtLogin:
            LoginItemManager().setEnabled(true)
        #else
        case .notchIsland, .sessions, .sessionNames, .openAtLogin:
            break
        #endif
        }
    }

    /// Where the menu bar clearance stands with the Accessibility
    /// permission, for `.sessionNames`'s "On" label; nil for every other
    /// feature and on iOS.
    static func accessibility(for feature: TourFeature, prefs: PreferencesModel) -> AccessibilityState? {
        #if os(macOS)
        feature == .sessionNames ? AccessibilityAccess.state(prefs: prefs) : nil
        #else
        nil
        #endif
    }

    /// Whether notifications are allowed, for `.alerts`.
    static func notificationsAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
}
