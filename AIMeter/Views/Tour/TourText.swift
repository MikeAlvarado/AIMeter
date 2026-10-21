import Foundation

/// Each tour step's words: what the feature is, in a line or two, and
/// what its button does where it has one.
enum TourText {
    static func title(_ feature: TourFeature) -> String {
        switch feature {
        case .welcome: String(localized: "Welcome to AIMeter")
        case .widgets: String(localized: "Widgets that keep score")
        case .alerts: String(localized: "Alerts before you hit the wall")
        case .colors: String(localized: "Yellow and red as you near a limit")
        case .notchIsland: String(localized: "Your limits in the notch")
        case .sessions: String(localized: "A pet for each Claude Code session")
        case .sessionNames: String(localized: "Names, without covering your menu bar")
        case .openAtLogin: String(localized: "Ready when your Mac is")
        case .connect: String(localized: "Connect your account")
        }
    }

    static func detail(_ feature: TourFeature) -> String {
        switch feature {
        case .welcome: String(localized: "Your AI subscriptions' limits at a glance: every window, how much is left, and when it resets.")
        case .widgets: String(localized: "Touch and hold the Home Screen, tap Edit, then Add Widget, and pick AIMeter. The Lock Screen has one too.")
        case .alerts: String(localized: "Allow notifications, then choose in each account which alerts you want: near a limit, an early run-out, a reset.")
        case .colors: String(localized: "Bars turn yellow above 70% used and red above 85%, so you see a limit coming.")
        case .notchIsland: String(localized: "Rest the cursor on the notch to see your figures, and click to see every account. It never takes focus.")
        case .sessions: String(localized: "Each session at work gets a pixel pet beside the notch. Install the hooks and AIMeter also knows the moment a session asks for permission.")
        case .sessionNames: String(localized: "Show the working session's name beside the notch. With Accessibility allowed, the island shrinks before it covers your menus or the icons on the right.")
        case .openAtLogin: String(localized: "Open AIMeter at login, so the menu bar, the notch and the widgets stay current.")
        case .connect: String(localized: "Sign in with your Claude account. AIMeter only ever reads your limits.")
        }
    }
}
