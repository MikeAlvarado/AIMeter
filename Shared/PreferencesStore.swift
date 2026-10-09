import Foundation
import SwiftUI
import UsageKit

enum DisplayMode: String, CaseIterable {
    case used, remaining

    var label: String {
        switch self {
        case .used: return String(localized: "Used")
        case .remaining: return String(localized: "Remaining")
        }
    }

    /// The word after a big figure: "42% left" / "42% used" (the medium
    /// widget's columns).
    var suffix: String {
        switch self {
        case .used: return String(localized: "used")
        case .remaining: return String(localized: "left")
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
    /// Dark by default on the Mac since 1.7 — the notch island is black
    /// and the app sits beside it; iOS keeps following the system. An
    /// install that ever chose a theme has the key written and keeps it;
    /// one that never did falls into this default, which is the one
    /// upgrade-visible change besides the island itself.
    #if os(macOS)
    var appearance: AppearanceMode = .dark
    #else
    var appearance: AppearanceMode = .system
    #endif
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

    /// Pre-`menuBarStyle` installs' one choice — gauge with or without the
    /// number. Only read at load time now, to derive `menuBarStyle` for an
    /// install that never picked a style; never written again (same
    /// "old keys stay inert" rule as the migrated notification keys).
    var menuBarShowsPercentage: Bool = true
    /// How the status item draws the primary account's usage. Defaults to
    /// what shipped first (gauge + number); see `MenuBarStyle.migrated`.
    var menuBarStyle: MenuBarStyle = .gaugeWithPercent
    /// The windows the `multi` style lists, in order (1–3, filtered at
    /// render time to the ones the primary account actually reports —
    /// same live-options rule as `glanceMetric`).
    var menuBarMetrics: [UsageWindow.Kind] = [.session, .weekly]
    /// Draws the label in `Theme.danger` once the window would be red on
    /// the dashboard (≥ 80 % used or provider-flagged critical). Off by
    /// default: the menu bar stays monochrome unless asked.
    var menuBarTintsAtDanger: Bool = false
    /// Appends the primary window's reset countdown ("· 1h 20m").
    var menuBarShowsResetCountdown: Bool = false
    /// Prefixes the primary account's nickname — only meaningful with
    /// two or more accounts, and only offered then.
    var menuBarShowsAccountName: Bool = false
    /// Whether the menu bar status item is present at all. Hiding it and the
    /// Dock icon together leaves no visible UI — relaunching the app is the
    /// way back in (see `AppDelegate.applicationShouldHandleReopen`).
    var statusItemVisible: Bool = true
    /// Drops the Dock icon and Cmd-Tab entry (`.accessory` activation
    /// policy), turning AIMeter into a menu-bar-only utility. The app keeps
    /// running and refreshing either way.
    var hideDockIcon: Bool = false

    // MARK: Notch island (macOS)
    //
    // The black panel fused to the notch (or the floating pill on a Mac
    // without one) — see "Notch island" under the presentation rules. On
    // by default on a Mac with a notch, the one deliberate exception to
    // "defaults never change an existing install", decided once by the
    // migration gated on `notchIslandMigrated`. The status item stays
    // until the user opens the island for the first time
    // (`notchIslandDiscovered`); the Settings toggle couples the two
    // immediately (`PreferencesModel.setNotchIsland(enabled:)`).

    /// Whether the island is shown at all. The struct's default is off;
    /// `AccountMigration.migrateNotchIslandIfNeeded` writes the real
    /// default once, at the first launch of 1.7: on for a Mac with a
    /// notch, off for one without (the floating pill is opt-in there —
    /// a capsule under the menu bar of an iMac is not a quiet upgrade).
    var notchIslandEnabled: Bool = false
    /// Which wings open beside the notch on the peek (and head the
    /// expanded island): both, left or right. Collapsed, the island is
    /// always the notch alone, so no menu title or status item is ever
    /// covered until the cursor asks. The pill ignores this.
    var notchIslandLayout: NotchIslandLayout = .bothSides
    /// The windows the collapsed wings list, in order (1–3, filtered at
    /// render time to what the primary account reports — the same
    /// live-options rule as `menuBarMetrics`).
    var notchIslandMetrics: [UsageWindow.Kind] = [.session, .weekly]
    /// Whether hovering opens the expanded island; off, only a click does.
    var notchIslandExpandsOnHover: Bool = true
    /// The one-time upgrade step that decided `notchIslandEnabled` from
    /// the hardware has run — written by `AccountMigration`, never cleared.
    var notchIslandMigrated: Bool = false
    /// The first-run reveal (the island peeks by itself once, with a
    /// caption) has been shown.
    var notchIslandRevealed: Bool = false
    /// The user has opened the island at least once. Until then the
    /// menu bar icon stays, whatever the coupling: an upgrade must not
    /// take the icon away before the user has found its replacement.
    var notchIslandDiscovered: Bool = false

    /// Whether refreshes also read the provider's public status page, so
    /// an outage shows as an incident instead of an account error. On by
    /// default — it is an anonymous GET of a public page, disclosed in
    /// Privacy & data — which means it must load through the presence
    /// check like the macOS chrome bools above.
    var checksServiceStatus: Bool = true
    // MARK: Claude Code usage (macOS)
    //
    // Off by default and opt-in: the CLI's logs are another app's files.
    /// Whether AIMeter reads `~/.claude/projects` for token counts.
    var claudeCodeUsageEnabled: Bool = false
    /// The Dashboard's invitation was dismissed ("Not now") — a
    /// tombstone, same shape as `autoDetectDeclined`.
    var claudeCodeUsageDismissed: Bool = false
    /// One "Claude Code today: …" line under the popover's accounts.
    var menuBarShowsClaudeCodeLine: Bool = false

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
        static let menuBarStyle = "pref.menuBarStyle"
        static let menuBarMetrics = "pref.menuBarMetrics"
        static let menuBarTintsAtDanger = "pref.menuBarTintsAtDanger"
        static let menuBarShowsResetCountdown = "pref.menuBarShowsResetCountdown"
        static let menuBarShowsAccountName = "pref.menuBarShowsAccountName"
        static let statusItemVisible = "pref.statusItemVisible"
        static let hideDockIcon = "pref.hideDockIcon"
        static let notchIslandEnabled = "pref.notchIslandEnabled"
        static let notchIslandLayout = "pref.notchIslandLayout"
        static let notchIslandMetrics = "pref.notchIslandMetrics"
        static let notchIslandExpandsOnHover = "pref.notchIslandExpandsOnHover"
        static let notchIslandMigrated = "pref.notchIslandMigrated"
        static let notchIslandRevealed = "pref.notchIslandRevealed"
        static let notchIslandDiscovered = "pref.notchIslandDiscovered"
        static let checksServiceStatus = "pref.checksServiceStatus"
        static let claudeCodeUsageEnabled = "pref.claudeCodeUsageEnabled"
        static let claudeCodeUsageDismissed = "pref.claudeCodeUsageDismissed"
        static let menuBarShowsClaudeCodeLine = "pref.menuBarShowsClaudeCodeLine"
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
        if let raw = defaults.string(forKey: Keys.menuBarStyle), let value = MenuBarStyle(rawValue: raw) {
            prefs.menuBarStyle = value
        } else {
            // No style ever chosen: keep exactly what the old toggle showed.
            prefs.menuBarStyle = MenuBarStyle.migrated(showsPercentage: prefs.menuBarShowsPercentage)
        }
        if let raw = defaults.stringArray(forKey: Keys.menuBarMetrics) {
            let kinds = raw.compactMap(UsageWindow.Kind.init(storageKey:))
            if !kinds.isEmpty { prefs.menuBarMetrics = kinds }
        }
        prefs.menuBarTintsAtDanger = defaults.bool(forKey: Keys.menuBarTintsAtDanger)
        prefs.menuBarShowsResetCountdown = defaults.bool(forKey: Keys.menuBarShowsResetCountdown)
        prefs.menuBarShowsAccountName = defaults.bool(forKey: Keys.menuBarShowsAccountName)
        prefs.statusItemVisible = bool(defaults, Keys.statusItemVisible, default: true)
        prefs.hideDockIcon = bool(defaults, Keys.hideDockIcon, default: false)
        prefs.notchIslandEnabled = defaults.bool(forKey: Keys.notchIslandEnabled)
        if let raw = defaults.string(forKey: Keys.notchIslandLayout), let value = NotchIslandLayout(rawValue: raw) {
            prefs.notchIslandLayout = value
        }
        if let raw = defaults.stringArray(forKey: Keys.notchIslandMetrics) {
            let kinds = raw.compactMap(UsageWindow.Kind.init(storageKey:))
            if !kinds.isEmpty { prefs.notchIslandMetrics = kinds }
        }
        prefs.notchIslandExpandsOnHover = bool(defaults, Keys.notchIslandExpandsOnHover, default: true)
        prefs.notchIslandMigrated = defaults.bool(forKey: Keys.notchIslandMigrated)
        prefs.notchIslandRevealed = defaults.bool(forKey: Keys.notchIslandRevealed)
        prefs.notchIslandDiscovered = defaults.bool(forKey: Keys.notchIslandDiscovered)
        prefs.checksServiceStatus = bool(defaults, Keys.checksServiceStatus, default: true)
        prefs.claudeCodeUsageEnabled = defaults.bool(forKey: Keys.claudeCodeUsageEnabled)
        prefs.claudeCodeUsageDismissed = defaults.bool(forKey: Keys.claudeCodeUsageDismissed)
        prefs.menuBarShowsClaudeCodeLine = defaults.bool(forKey: Keys.menuBarShowsClaudeCodeLine)
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
