import Foundation

/// Identifiers shared between the app and the widget extension.
/// The App Group must match the entitlements of both targets exactly.
enum AppConfig {
    static let appGroupID = "group.com.mikealvarado.aimeter"
    static let keychainService = "com.mikealvarado.aimeter"
    /// Keychain access group shared by app and widget so the widget can
    /// read credentials and refresh usage itself. On iOS the App Group
    /// doubles as a keychain group; on macOS the menu bar app feeds the
    /// widget instead, and unsandboxed keychain groups behave differently.
    #if os(iOS)
    static let keychainAccessGroup: String? = appGroupID
    #else
    static let keychainAccessGroup: String? = nil
    #endif
    static let refreshTaskID = "com.mikealvarado.aimeter.refresh"
    static let widgetKind = "AIMeterUsage"
    /// Single-window widget: shows one provider/window the user picks from
    /// the widget's own Edit Widget configuration.
    static let singleWidgetKind = "AIMeterSingleUsage"
    static let refreshInterval: TimeInterval = 15 * 60
    /// A snapshot older than this is flagged as stale in widgets.
    static let staleAfter: TimeInterval = 30 * 60
    /// Minimum interval between a widget's own timeline reloads,
    /// independent of the user's display cadence. WidgetKit budgets
    /// background refreshes (~a few dozen a day); requesting every 15 min
    /// exhausts that budget and the system stops refreshing the widget —
    /// then even ignores app-initiated `reloadAllTimelines()` until the
    /// budget replenishes (next day). This floor keeps the widget in
    /// budget; the app still pushes fresh data on foreground for active use.
    static let widgetRefreshFloor: TimeInterval = 30 * 60
}
