import Foundation
import Observation
import UsageKit
import WidgetKit

/// Observable wrapper used by the app; every change writes through to the
/// App Group immediately. One stored `Preferences` value behind computed
/// accessors, so the field list exists once (`Preferences` itself) rather
/// than being repeated here in the properties, the initializer, and a
/// snapshot builder; `@Observable` tracks reads and writes through the
/// stored value, which is all the bindings need. Every setter skips a
/// write of the value already held: with one stored struct, any write
/// invalidates every reader of every field, and a scene that writes its
/// binding back during body evaluation (`MenuBarExtra(isInserted:)`)
/// would otherwise re-evaluate the App body forever — a launch crash by
/// stack overflow. The guard also keeps no-op writes from reloading
/// widget timelines.
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
        set { guard stored.displayMode != newValue else { return }; stored.displayMode = newValue; persist(newValue.rawValue, Preferences.Keys.displayMode, reloadsWidgets: true) }
    }
    var resetStyle: ResetStyle {
        get { stored.resetStyle }
        set { guard stored.resetStyle != newValue else { return }; stored.resetStyle = newValue; persist(newValue.rawValue, Preferences.Keys.resetStyle, reloadsWidgets: true) }
    }
    var refreshCadence: RefreshCadence {
        get { stored.refreshCadence }
        set { guard stored.refreshCadence != newValue else { return }; stored.refreshCadence = newValue; persist(newValue.rawValue, Preferences.Keys.refreshCadence, reloadsWidgets: true) }
    }
    var appearance: AppearanceMode {
        get { stored.appearance }
        set { guard stored.appearance != newValue else { return }; stored.appearance = newValue; persist(newValue.rawValue, Preferences.Keys.appearance, reloadsWidgets: false) }
    }
    var modelSlotFallback: ModelSlotFallback {
        get { stored.modelSlotFallback }
        set { guard stored.modelSlotFallback != newValue else { return }; stored.modelSlotFallback = newValue; persist(newValue.rawValue, Preferences.Keys.modelSlotFallback, reloadsWidgets: true) }
    }
    var glanceMetric: UsageWindow.Kind {
        get { stored.glanceMetric }
        set { guard stored.glanceMetric != newValue else { return }; stored.glanceMetric = newValue; persist(newValue.storageKey, Preferences.Keys.glanceMetric, reloadsWidgets: true) }
    }
    var showCreditsAmount: Bool {
        get { stored.showCreditsAmount }
        set { guard stored.showCreditsAmount != newValue else { return }; stored.showCreditsAmount = newValue; persist(newValue, Preferences.Keys.showCreditsAmount, reloadsWidgets: true) }
    }
    var primaryAccountID: String? {
        get { stored.primaryAccountID }
        set { guard stored.primaryAccountID != newValue else { return }; stored.primaryAccountID = newValue; persist(newValue, Preferences.Keys.primaryAccountID, reloadsWidgets: false) }
    }
    var menuBarStyle: MenuBarStyle {
        get { stored.menuBarStyle }
        set { guard stored.menuBarStyle != newValue else { return }; stored.menuBarStyle = newValue; persist(newValue.rawValue, Preferences.Keys.menuBarStyle, reloadsWidgets: false) }
    }
    var menuBarMetrics: [UsageWindow.Kind] {
        get { stored.menuBarMetrics }
        set { guard stored.menuBarMetrics != newValue else { return }; stored.menuBarMetrics = newValue; persist(newValue.map(\.storageKey), Preferences.Keys.menuBarMetrics, reloadsWidgets: false) }
    }
    var menuBarTintsAtDanger: Bool {
        get { stored.menuBarTintsAtDanger }
        set { guard stored.menuBarTintsAtDanger != newValue else { return }; stored.menuBarTintsAtDanger = newValue; persist(newValue, Preferences.Keys.menuBarTintsAtDanger, reloadsWidgets: false) }
    }
    var menuBarShowsResetCountdown: Bool {
        get { stored.menuBarShowsResetCountdown }
        set { guard stored.menuBarShowsResetCountdown != newValue else { return }; stored.menuBarShowsResetCountdown = newValue; persist(newValue, Preferences.Keys.menuBarShowsResetCountdown, reloadsWidgets: false) }
    }
    var menuBarShowsAccountName: Bool {
        get { stored.menuBarShowsAccountName }
        set { guard stored.menuBarShowsAccountName != newValue else { return }; stored.menuBarShowsAccountName = newValue; persist(newValue, Preferences.Keys.menuBarShowsAccountName, reloadsWidgets: false) }
    }
    var statusItemVisible: Bool {
        get { stored.statusItemVisible }
        set { guard stored.statusItemVisible != newValue else { return }; stored.statusItemVisible = newValue; persist(newValue, Preferences.Keys.statusItemVisible, reloadsWidgets: false) }
    }
    var hideDockIcon: Bool {
        get { stored.hideDockIcon }
        set { guard stored.hideDockIcon != newValue else { return }; stored.hideDockIcon = newValue; persist(newValue, Preferences.Keys.hideDockIcon, reloadsWidgets: false) }
    }
    var notchIslandEnabled: Bool {
        get { stored.notchIslandEnabled }
        set { guard stored.notchIslandEnabled != newValue else { return }; stored.notchIslandEnabled = newValue; persist(newValue, Preferences.Keys.notchIslandEnabled, reloadsWidgets: false) }
    }
    var notchIslandLayout: NotchIslandLayout {
        get { stored.notchIslandLayout }
        set { guard stored.notchIslandLayout != newValue else { return }; stored.notchIslandLayout = newValue; persist(newValue.rawValue, Preferences.Keys.notchIslandLayout, reloadsWidgets: false) }
    }
    var notchIslandMetrics: [UsageWindow.Kind] {
        get { stored.notchIslandMetrics }
        set { guard stored.notchIslandMetrics != newValue else { return }; stored.notchIslandMetrics = newValue; persist(newValue.map(\.storageKey), Preferences.Keys.notchIslandMetrics, reloadsWidgets: false) }
    }
    var notchIslandExpandsOnHover: Bool {
        get { stored.notchIslandExpandsOnHover }
        set { guard stored.notchIslandExpandsOnHover != newValue else { return }; stored.notchIslandExpandsOnHover = newValue; persist(newValue, Preferences.Keys.notchIslandExpandsOnHover, reloadsWidgets: false) }
    }
    var notchIslandMigrated: Bool {
        get { stored.notchIslandMigrated }
        set { guard stored.notchIslandMigrated != newValue else { return }; stored.notchIslandMigrated = newValue; persist(newValue, Preferences.Keys.notchIslandMigrated, reloadsWidgets: false) }
    }
    var notchIslandRevealed: Bool {
        get { stored.notchIslandRevealed }
        set { guard stored.notchIslandRevealed != newValue else { return }; stored.notchIslandRevealed = newValue; persist(newValue, Preferences.Keys.notchIslandRevealed, reloadsWidgets: false) }
    }
    var notchIslandDiscovered: Bool {
        get { stored.notchIslandDiscovered }
        set { guard stored.notchIslandDiscovered != newValue else { return }; stored.notchIslandDiscovered = newValue; persist(newValue, Preferences.Keys.notchIslandDiscovered, reloadsWidgets: false) }
    }
    var checksServiceStatus: Bool {
        get { stored.checksServiceStatus }
        set { guard stored.checksServiceStatus != newValue else { return }; stored.checksServiceStatus = newValue; persist(newValue, Preferences.Keys.checksServiceStatus, reloadsWidgets: false) }
    }
    var claudeCodeUsageEnabled: Bool {
        get { stored.claudeCodeUsageEnabled }
        set { guard stored.claudeCodeUsageEnabled != newValue else { return }; stored.claudeCodeUsageEnabled = newValue; persist(newValue, Preferences.Keys.claudeCodeUsageEnabled, reloadsWidgets: false) }
    }
    var claudeCodeUsageDismissed: Bool {
        get { stored.claudeCodeUsageDismissed }
        set { guard stored.claudeCodeUsageDismissed != newValue else { return }; stored.claudeCodeUsageDismissed = newValue; persist(newValue, Preferences.Keys.claudeCodeUsageDismissed, reloadsWidgets: false) }
    }
    var menuBarShowsClaudeCodeLine: Bool {
        get { stored.menuBarShowsClaudeCodeLine }
        set { guard stored.menuBarShowsClaudeCodeLine != newValue else { return }; stored.menuBarShowsClaudeCodeLine = newValue; persist(newValue, Preferences.Keys.menuBarShowsClaudeCodeLine, reloadsWidgets: false) }
    }

    var lastScheduledAt: Date? {
        defaults.object(forKey: Preferences.Keys.lastScheduledAt) as? Date
    }

    func toggleResetStyle() {
        resetStyle = resetStyle == .relative ? .absolute : .relative
    }

    /// The island and the status item are coupled: turning the island on
    /// hides the menu bar icon, turning it off brings the icon back. "Hide
    /// menu bar icon" still works on its own afterwards — the two can be
    /// shown together if the user re-enables the icon by hand. Settings
    /// drives the chrome itself through `AppChrome.setNotchIsland`. A
    /// deliberate switch here counts as having discovered the island.
    func setNotchIsland(enabled: Bool) {
        notchIslandEnabled = enabled
        statusItemVisible = !enabled
        if enabled { notchIslandDiscovered = true }
    }

    /// The user opened the island for the first time: the coupling the
    /// upgrade deferred applies now — the icon goes, its replacement has
    /// been found. Returns whether this call was that first time.
    @discardableResult
    func markNotchIslandDiscovered() -> Bool {
        guard !notchIslandDiscovered else { return false }
        notchIslandDiscovered = true
        statusItemVisible = false
        return true
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
