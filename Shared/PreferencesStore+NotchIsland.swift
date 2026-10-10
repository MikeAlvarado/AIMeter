import Foundation
import UsageKit

/// The notch island's keys and their loading, split out of
/// `PreferencesStore.swift` by feature. The stored properties stay on
/// `Preferences` itself (Swift keeps stored properties in the type's own
/// declaration); everything about reading them back lives here.
extension Preferences.Keys {
    static let notchIslandEnabled = "pref.notchIslandEnabled"
    static let notchIslandLayout = "pref.notchIslandLayout"
    static let notchIslandMetrics = "pref.notchIslandMetrics"
    static let notchIslandExpandsOnHover = "pref.notchIslandExpandsOnHover"
    static let notchIslandMigrated = "pref.notchIslandMigrated"
    static let notchIslandRevealed = "pref.notchIslandRevealed"
    static let notchIslandDiscovered = "pref.notchIslandDiscovered"
    static let notchIslandHoverDelay = "pref.notchIslandHoverDelay"
    static let notchIslandHiddenFromCapture = "pref.notchIslandHiddenFromCapture"
    static let notchIslandForm = "pref.notchIslandForm"
    static let notchIslandHeightMode = "pref.notchIslandHeightMode"
    static let notchIslandCustomHeight = "pref.notchIslandCustomHeight"
    static let notchIslandHidesUntilHover = "pref.notchIslandHidesUntilHover"
    static let notchIslandHidesInFullScreen = "pref.notchIslandHidesInFullScreen"
}

extension Preferences {
    /// Reads every island key back. Anything unreadable — an unknown raw
    /// value, a number out of range, NaN — falls back to (or is clamped
    /// into) what the struct declares, so a bad write can never leave the
    /// island unlaid-out or its timer negative.
    mutating func loadNotchIsland(from defaults: UserDefaults) {
        notchIslandEnabled = defaults.bool(forKey: Keys.notchIslandEnabled)
        if let raw = defaults.string(forKey: Keys.notchIslandLayout), let value = NotchIslandLayout(rawValue: raw) {
            notchIslandLayout = value
        }
        if let raw = defaults.stringArray(forKey: Keys.notchIslandMetrics) {
            let kinds = raw.compactMap(UsageWindow.Kind.init(storageKey:))
            if !kinds.isEmpty { notchIslandMetrics = kinds }
        }
        notchIslandExpandsOnHover = Self.bool(defaults, Keys.notchIslandExpandsOnHover, default: true)
        notchIslandMigrated = defaults.bool(forKey: Keys.notchIslandMigrated)
        notchIslandRevealed = defaults.bool(forKey: Keys.notchIslandRevealed)
        notchIslandDiscovered = defaults.bool(forKey: Keys.notchIslandDiscovered)
        if let value = defaults.object(forKey: Keys.notchIslandHoverDelay) as? Double {
            notchIslandHoverDelay = NotchIslandInteraction.clampedDwell(seconds: value)
        }
        notchIslandHiddenFromCapture = defaults.bool(forKey: Keys.notchIslandHiddenFromCapture)
        if let raw = defaults.string(forKey: Keys.notchIslandForm), let value = NotchIslandForm(rawValue: raw) {
            notchIslandForm = value
        }
        if let raw = defaults.string(forKey: Keys.notchIslandHeightMode), let value = NotchIslandHeightMode(rawValue: raw) {
            notchIslandHeightMode = value
        }
        if let value = defaults.object(forKey: Keys.notchIslandCustomHeight) as? Double {
            notchIslandCustomHeight = Double(NotchIslandGeometry.clampedHeight(CGFloat(value)))
        }
        notchIslandHidesUntilHover = defaults.bool(forKey: Keys.notchIslandHidesUntilHover)
        notchIslandHidesInFullScreen = Self.bool(defaults, Keys.notchIslandHidesInFullScreen, default: true)
    }

    /// The geometry options a screen without a notch is laid out with.
    var notchIslandOptions: NotchIslandGeometry.Options {
        NotchIslandGeometry.Options(
            form: notchIslandForm,
            height: notchIslandHeightMode == .custom ? CGFloat(notchIslandCustomHeight) : nil
        )
    }
}
