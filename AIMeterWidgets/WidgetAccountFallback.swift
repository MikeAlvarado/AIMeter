import UsageKit

/// The account a widget falls back to when its own per-instance
/// configuration hasn't resolved yet — a known WidgetKit timing edge case
/// right after a widget is first placed, before the intent's own default
/// selection has been applied. The first connected account (registry
/// order), or the legacy sentinel if none are connected yet. Shared by
/// `UsageWidget` and `SingleUsageWidget`'s `entry(for:)` — previously
/// duplicated identically in both.
enum WidgetAccountFallback {
    static func resolve() -> (accountID: String, accountName: String) {
        if let first = AccountRegistryStore(suiteName: AppConfig.appGroupID)?.accounts().first {
            return (first.accountID, first.displayName)
        }
        return (ClaudeKeychainCredentialSource.legacyAccountID, "Claude")
    }
}
