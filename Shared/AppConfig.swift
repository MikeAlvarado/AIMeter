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
    static let refreshInterval: TimeInterval = 15 * 60
    /// A snapshot older than this is flagged as stale in widgets.
    static let staleAfter: TimeInterval = 30 * 60
}
