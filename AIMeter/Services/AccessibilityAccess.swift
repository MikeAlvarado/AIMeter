#if os(macOS)
import ApplicationServices
import Foundation

/// The one place AIMeter reads macOS's Accessibility permission and asks
/// for it, for "Avoid covering the menu bar" (see `AccessibilityState`).
/// Reading is free and silent; asking shows the system's prompt, so it
/// happens only from the user's own switch or the tour's button, and only
/// while the permission never worked: a copy that lost it to a different
/// signature is told how to mend it instead.
@MainActor
enum AccessibilityAccess {
    /// Privacy & Security, Accessibility.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    /// Whether macOS trusts this copy now. Silent.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// The state as it reads now, writing nothing (safe inside a view's
    /// body).
    static func state(prefs: PreferencesModel) -> AccessibilityState {
        AccessibilityState(trusted: isTrusted, confirmedBefore: prefs.claudeSessionsAccessibilityConfirmed)
    }

    /// The state, remembering a permission that works
    /// (`claudeSessionsAccessibilityConfirmed`), so that a copy which later
    /// loses it can say why. Not from a view's body: it may write a
    /// preference.
    @discardableResult
    static func check(prefs: PreferencesModel) -> AccessibilityState {
        let state = state(prefs: prefs)
        if state == .granted {
            prefs.claudeSessionsAccessibilityConfirmed = true
        }
        return state
    }

    /// Asks with the system's prompt where `AccessibilityState.mayPrompt`
    /// allows it, and returns the state after.
    @discardableResult
    static func request(prefs: PreferencesModel) -> AccessibilityState {
        guard check(prefs: prefs).mayPrompt else { return check(prefs: prefs) }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        return check(prefs: prefs)
    }
}

extension AccessibilityState {
    /// What to do about it, while the feature is on and this copy isn't
    /// trusted; nil once it is.
    var remedy: String? {
        switch self {
        case .granted:
            nil
        case .notGranted:
            String(localized: "Allow AIMeter in Privacy & Security, Accessibility.")
        case .lostForThisCopy:
            String(localized: "This copy of AIMeter needs Accessibility again. In System Settings, remove AIMeter with − if it's in the list, then add it with +.")
        }
    }
}
#endif
