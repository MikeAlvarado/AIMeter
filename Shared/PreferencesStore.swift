import Foundation
import Observation
import SwiftUI
import UsageKit
import WidgetKit

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
    case minutes30 = 1800
    case hour1 = 3600
    case hours3 = 10800

    var label: String {
        switch self {
        case .minutes30: return String(localized: "Every 30 minutes")
        case .hour1: return String(localized: "Every hour")
        case .hours3: return String(localized: "Every 3 hours")
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
    var refreshCadence: RefreshCadence = .minutes30
    var appearance: AppearanceMode = .system
    var modelSlotFallback: ModelSlotFallback = .auto
    /// Which single window the compact "at a glance" surfaces show: the
    /// macOS menu bar label and iOS's Lock Screen circular gauge (both
    /// have room for exactly one number). Stored as a plain `UsageWindow.Kind`
    /// rather than a fixed enum so it scales to whatever the account
    /// actually reports — a per-model window (e.g. Fable on Max) or
    /// Credits, not just Session/Weekly.
    var glanceMetric: UsageWindow.Kind = .session
    /// Shows the Credits row's used/limit amounts in place of a reset
    /// line (a spend cap has no rollover date to show one). Off by
    /// default — opt-in extra detail, only visible when a Credits row is
    /// actually showing.
    var showCreditsAmount: Bool = false
    /// Which connected account the macOS status item's gauge tracks.
    /// `MenuBarExtra` has no per-instance configuration the way widgets do
    /// (there's exactly one status item), so this is the one place a
    /// "primary" account has to be picked explicitly. nil (or an account
    /// that's since been disconnected) falls back to the first connected
    /// account — see `MacChromeSettings`/`AIMeterApp`.
    var primaryAccountID: String?

    // MARK: macOS chrome
    //
    // How the app presents itself on the Mac, independent of any provider's
    // data — which is why these live here and surface in app-wide Settings
    // rather than in Claude's Provider Detail alongside `glanceMetric`.
    // All three default to the behavior shipped before they existed, so an
    // upgrade never changes what an existing install looks like.

    /// Whether the menu bar label spells out the `glanceMetric` percentage
    /// next to the gauge, or shows the gauge alone. Icon-only still carries
    /// the number in the tooltip and the accessibility label.
    var menuBarShowsPercentage: Bool = true
    /// Whether the menu bar status item is present at all. Hiding it and the
    /// Dock icon together leaves no visible UI — relaunching the app is the
    /// way back in (see `AppDelegate.applicationShouldHandleReopen`).
    var statusItemVisible: Bool = true
    /// Drops the Dock icon and Cmd-Tab entry (`.accessory` activation
    /// policy), turning AIMeter into a menu-bar-only utility. The app keeps
    /// running and refreshing either way.
    var hideDockIcon: Bool = false

    var lastScheduledAt: Date?

    enum Keys {
        static let displayMode = "pref.displayMode"
        static let resetStyle = "pref.resetStyle"
        static let refreshCadence = "pref.refreshCadence"
        static let appearance = "pref.appearance"
        static let modelSlotFallback = "pref.modelSlotFallback"
        static let glanceMetric = "pref.glanceMetric"
        static let showCreditsAmount = "pref.showCreditsAmount"
        static let primaryAccountID = "pref.primaryAccountID"
        static let menuBarShowsPercentage = "pref.menuBarShowsPercentage"
        static let statusItemVisible = "pref.statusItemVisible"
        static let hideDockIcon = "pref.hideDockIcon"
        static let lastScheduledAt = "pref.lastScheduledAt"
        static let autoDetectDeclined = "pref.autoDetectDeclined"
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
        if let raw = defaults.string(forKey: Keys.glanceMetric), let value = UsageWindow.Kind(storageKey: raw) {
            prefs.glanceMetric = value
        }
        prefs.showCreditsAmount = defaults.bool(forKey: Keys.showCreditsAmount)
        prefs.primaryAccountID = defaults.string(forKey: Keys.primaryAccountID)
        prefs.menuBarShowsPercentage = bool(defaults, Keys.menuBarShowsPercentage, default: true)
        prefs.statusItemVisible = bool(defaults, Keys.statusItemVisible, default: true)
        prefs.hideDockIcon = bool(defaults, Keys.hideDockIcon, default: false)
        if let timestamp = defaults.object(forKey: Keys.lastScheduledAt) as? Date {
            prefs.lastScheduledAt = timestamp
        }
        return prefs
    }

    /// `UserDefaults.bool(forKey:)` reports `false` for a key that was never
    /// written, which silently flips any preference whose default is `true`
    /// for every install that upgrades without touching the setting. The
    /// presence check keeps the struct's own default authoritative until the
    /// user actually chooses.
    private static func bool(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    static func recordScheduled(_ date: Date = Date()) {
        groupDefaults.set(date, forKey: Keys.lastScheduledAt)
    }

    /// macOS only in meaning: the user explicitly disconnected the account
    /// that mirrors Claude Code's own login. Without this tombstone
    /// `UsageModel.loadAccounts()` would speculatively re-mirror that login
    /// on the very next launch (the CLI's Keychain item is still there —
    /// disconnecting only clears the app's fallback copy), so the account
    /// the user just removed would quietly come back. Cleared by the
    /// "Use Claude Code's login instead" affordance on the disconnected
    /// Dashboard card.
    static var autoDetectDeclined: Bool {
        get { groupDefaults.bool(forKey: Keys.autoDetectDeclined) }
        set { groupDefaults.set(newValue, forKey: Keys.autoDetectDeclined) }
    }
}

/// Observable wrapper used by the app; every change writes through to the
/// App Group immediately. One stored `Preferences` value behind computed
/// accessors, so the field list exists once (`Preferences` itself) rather
/// than being repeated here in the properties, the initializer, and a
/// snapshot builder; `@Observable` tracks reads and writes through the
/// stored value, which is all the bindings need.
@Observable
final class PreferencesModel {
    private var stored: Preferences
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var widgetReload: Task<Void, Never>?

    init(defaults: UserDefaults = Preferences.groupDefaults) {
        self.defaults = defaults
        stored = Preferences.load(from: defaults)
    }

    var displayMode: DisplayMode {
        get { stored.displayMode }
        set { stored.displayMode = newValue; persist(newValue.rawValue, Preferences.Keys.displayMode, reloadsWidgets: true) }
    }
    var resetStyle: ResetStyle {
        get { stored.resetStyle }
        set { stored.resetStyle = newValue; persist(newValue.rawValue, Preferences.Keys.resetStyle, reloadsWidgets: true) }
    }
    var refreshCadence: RefreshCadence {
        get { stored.refreshCadence }
        set { stored.refreshCadence = newValue; persist(newValue.rawValue, Preferences.Keys.refreshCadence, reloadsWidgets: true) }
    }
    var appearance: AppearanceMode {
        get { stored.appearance }
        set { stored.appearance = newValue; persist(newValue.rawValue, Preferences.Keys.appearance, reloadsWidgets: false) }
    }
    var modelSlotFallback: ModelSlotFallback {
        get { stored.modelSlotFallback }
        set { stored.modelSlotFallback = newValue; persist(newValue.rawValue, Preferences.Keys.modelSlotFallback, reloadsWidgets: true) }
    }
    var glanceMetric: UsageWindow.Kind {
        get { stored.glanceMetric }
        set { stored.glanceMetric = newValue; persist(newValue.storageKey, Preferences.Keys.glanceMetric, reloadsWidgets: true) }
    }
    var showCreditsAmount: Bool {
        get { stored.showCreditsAmount }
        set { stored.showCreditsAmount = newValue; persist(newValue, Preferences.Keys.showCreditsAmount, reloadsWidgets: true) }
    }
    var primaryAccountID: String? {
        get { stored.primaryAccountID }
        set { stored.primaryAccountID = newValue; persist(newValue, Preferences.Keys.primaryAccountID, reloadsWidgets: false) }
    }
    var menuBarShowsPercentage: Bool {
        get { stored.menuBarShowsPercentage }
        set { stored.menuBarShowsPercentage = newValue; persist(newValue, Preferences.Keys.menuBarShowsPercentage, reloadsWidgets: false) }
    }
    var statusItemVisible: Bool {
        get { stored.statusItemVisible }
        set { stored.statusItemVisible = newValue; persist(newValue, Preferences.Keys.statusItemVisible, reloadsWidgets: false) }
    }
    var hideDockIcon: Bool {
        get { stored.hideDockIcon }
        set { stored.hideDockIcon = newValue; persist(newValue, Preferences.Keys.hideDockIcon, reloadsWidgets: false) }
    }

    var lastScheduledAt: Date? {
        defaults.object(forKey: Preferences.Keys.lastScheduledAt) as? Date
    }

    func toggleResetStyle() {
        resetStyle = resetStyle == .relative ? .absolute : .relative
    }

    /// The current values as a plain `Preferences`, for code paths written
    /// against the value type (widgets' rendering helpers).
    var snapshot: Preferences {
        var prefs = stored
        prefs.lastScheduledAt = lastScheduledAt
        return prefs
    }

    /// Writes one key through to the App Group. `reloadsWidgets` is true
    /// for the prefs widgets read when they render: nothing re-renders
    /// them until their next timeline reload — up to the refresh floor
    /// away, or on macOS until the app's next scheduled fetch — so one
    /// coalesced reload per burst of changes (a segmented pill tapped three
    /// times in a row is one reload, not three against WidgetKit's per-kind
    /// budget) closes that gap.
    private func persist(_ value: Any?, _ key: String, reloadsWidgets: Bool) {
        defaults.set(value, forKey: key)
        guard reloadsWidgets else { return }
        widgetReload?.cancel()
        widgetReload = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
