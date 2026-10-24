import Foundation

/// The Claude Code sessions' keys and their loading (see "Claude Code
/// sessions" in the repo-root CLAUDE.md), split out like the notch
/// island's; the stored properties stay on `Preferences` itself.
extension Preferences.Keys {
    static let claudeSessionsEnabled = "pref.claudeSessionsEnabled"
    static let claudeSessionsPets = "pref.claudeSessionsPets"
    static let claudeSessionsShowsName = "pref.claudeSessionsShowsName"
    static let claudeSessionsAvoidsMenus = "pref.claudeSessionsAvoidsMenus"
    static let claudeSessionsAccessibilityConfirmed = "pref.claudeSessionsAccessibilityConfirmed"
    static let claudeSessionsNotify = "pref.claudeSessionsNotify"
    static let claudeSessionsAnswers = "pref.claudeSessionsAnswers"
    static let claudeSessionsHooksDismissed = "pref.claudeSessionsHooksDismissed"
}

extension Preferences {
    mutating func loadClaudeSessions(from defaults: UserDefaults) {
        claudeSessionsEnabled = Self.bool(defaults, Keys.claudeSessionsEnabled, default: true)
        claudeSessionsPets = Self.bool(defaults, Keys.claudeSessionsPets, default: true)
        claudeSessionsShowsName = defaults.bool(forKey: Keys.claudeSessionsShowsName)
        claudeSessionsAvoidsMenus = defaults.bool(forKey: Keys.claudeSessionsAvoidsMenus)
        claudeSessionsAccessibilityConfirmed = defaults.bool(forKey: Keys.claudeSessionsAccessibilityConfirmed)
        claudeSessionsNotify = defaults.bool(forKey: Keys.claudeSessionsNotify)
        claudeSessionsAnswers = defaults.bool(forKey: Keys.claudeSessionsAnswers)
        claudeSessionsHooksDismissed = defaults.bool(forKey: Keys.claudeSessionsHooksDismissed)
    }
}
