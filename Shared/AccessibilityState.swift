import Foundation

/// Where "Avoid covering the menu bar" stands with macOS's Accessibility
/// permission: what Settings' Sessions card and the tour's card say, and
/// whether either may show the system's prompt (see "Claude Code
/// sessions" in the repo-root CLAUDE.md). Pure: from `AXIsProcessTrusted()`
/// and whether the permission ever worked for AIMeter
/// (`Preferences.claudeSessionsAccessibilityConfirmed`).
enum AccessibilityState: Equatable, Sendable {
    /// macOS trusts this copy.
    case granted
    /// It never has: the system's prompt, then AIMeter's switch in
    /// Privacy & Security, Accessibility.
    case notGranted
    /// It did once, and this copy isn't trusted. macOS keeps the permission
    /// with the signature of the copy it was given to, so a copy signed
    /// another way (a development build and a release, or the source built
    /// under another team) needs it again while System Settings still shows
    /// AIMeter on, and switching it off and on there doesn't carry it over;
    /// removing AIMeter with − and adding it back with + does (measured on
    /// macOS 27, 2026-10-15). A permission switched off in System Settings
    /// looks the same from here.
    case lostForThisCopy

    init(trusted: Bool, confirmedBefore: Bool) {
        if trusted {
            self = .granted
        } else if confirmedBefore {
            self = .lostForThisCopy
        } else {
            self = .notGranted
        }
    }

    /// Whether turning the feature on may show the system's prompt: only
    /// while the permission never worked. A lost one is mended in System
    /// Settings, and a prompt for a permission System Settings shows as on
    /// is what confused (3.0.0 over a development build, 2026-10-15).
    var mayPrompt: Bool { self == .notGranted }
}
