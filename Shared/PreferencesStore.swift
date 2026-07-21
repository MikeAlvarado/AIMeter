import Foundation
import Observation
import SwiftUI

enum DisplayMode: String, CaseIterable {
    case used, remaining

    var label: String {
        switch self {
        case .used: return String(localized: "Used")
        case .remaining: return String(localized: "Remaining")
        }
    }
}

enum ResetStyle: String, CaseIterable {
    case relative, absolute

    var label: String {
        switch self {
        case .relative: return String(localized: "Relative")
        case .absolute: return String(localized: "Absolute")
        }
    }
}

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    /// nil follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// What the third usage slot shows when the plan reports no per-model
/// window (e.g. Claude Pro without Fable 5's own weekly limit).
enum ModelSlotFallback: String, CaseIterable {
    /// Shows the credits row exactly when the account's spend/credits
    /// status is enabled, hides it otherwise — no manual choice needed.
    case auto, hidden, credits

    var label: String {
        switch self {
        case .auto: return String(localized: "Auto")
        case .hidden: return String(localized: "Hidden")
        case .credits: return String(localized: "Credits")
        }
    }
}

enum RefreshCadence: Int, CaseIterable {
    case minutes15 = 900
    case minutes30 = 1800
    case hour1 = 3600

    var label: String {
        switch self {
        case .minutes15: return String(localized: "Every 15 minutes")
        case .minutes30: return String(localized: "Every 30 minutes")
        case .hour1: return String(localized: "Every hour")
        }
    }

    var interval: TimeInterval { TimeInterval(rawValue) }
}

/// Display preferences, persisted in the App Group so widgets honor them.
/// Plain value type — widgets load it once per timeline; the app wraps it
/// in `PreferencesModel` for observation.
struct Preferences: Sendable {
    var displayMode: DisplayMode = .used
    var resetStyle: ResetStyle = .relative
    var refreshCadence: RefreshCadence = .minutes15
    var appearance: AppearanceMode = .system
    var modelSlotFallback: ModelSlotFallback = .auto
    var lastScheduledAt: Date?

    enum Keys {
        static let displayMode = "pref.displayMode"
        static let resetStyle = "pref.resetStyle"
        static let refreshCadence = "pref.refreshCadence"
        static let appearance = "pref.appearance"
        static let modelSlotFallback = "pref.modelSlotFallback"
        static let lastScheduledAt = "pref.lastScheduledAt"
    }

    static var groupDefaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    static func load(from defaults: UserDefaults = groupDefaults) -> Preferences {
        var prefs = Preferences()
        if let raw = defaults.string(forKey: Keys.displayMode), let value = DisplayMode(rawValue: raw) {
            prefs.displayMode = value
        }
        if let raw = defaults.string(forKey: Keys.resetStyle), let value = ResetStyle(rawValue: raw) {
            prefs.resetStyle = value
        }
        if let value = RefreshCadence(rawValue: defaults.integer(forKey: Keys.refreshCadence)) {
            prefs.refreshCadence = value
        }
        if let raw = defaults.string(forKey: Keys.appearance), let value = AppearanceMode(rawValue: raw) {
            prefs.appearance = value
        }
        if let raw = defaults.string(forKey: Keys.modelSlotFallback), let value = ModelSlotFallback(rawValue: raw) {
            prefs.modelSlotFallback = value
        }
        if let timestamp = defaults.object(forKey: Keys.lastScheduledAt) as? Date {
            prefs.lastScheduledAt = timestamp
        }
        return prefs
    }

    static func recordScheduled(_ date: Date = Date()) {
        groupDefaults.set(date, forKey: Keys.lastScheduledAt)
    }
}

/// Observable wrapper used by the app; every change writes through to the
/// App Group immediately.
@Observable
final class PreferencesModel {
    var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Preferences.Keys.displayMode) }
    }
    var resetStyle: ResetStyle {
        didSet { defaults.set(resetStyle.rawValue, forKey: Preferences.Keys.resetStyle) }
    }
    var refreshCadence: RefreshCadence {
        didSet { defaults.set(refreshCadence.rawValue, forKey: Preferences.Keys.refreshCadence) }
    }
    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Preferences.Keys.appearance) }
    }
    var modelSlotFallback: ModelSlotFallback {
        didSet { defaults.set(modelSlotFallback.rawValue, forKey: Preferences.Keys.modelSlotFallback) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = Preferences.groupDefaults) {
        self.defaults = defaults
        let loaded = Preferences.load(from: defaults)
        displayMode = loaded.displayMode
        resetStyle = loaded.resetStyle
        refreshCadence = loaded.refreshCadence
        appearance = loaded.appearance
        modelSlotFallback = loaded.modelSlotFallback
    }

    var lastScheduledAt: Date? {
        defaults.object(forKey: Preferences.Keys.lastScheduledAt) as? Date
    }

    func toggleResetStyle() {
        resetStyle = resetStyle == .relative ? .absolute : .relative
    }

    var snapshot: Preferences {
        var prefs = Preferences()
        prefs.displayMode = displayMode
        prefs.resetStyle = resetStyle
        prefs.refreshCadence = refreshCadence
        prefs.appearance = appearance
        prefs.modelSlotFallback = modelSlotFallback
        prefs.lastScheduledAt = lastScheduledAt
        return prefs
    }
}
