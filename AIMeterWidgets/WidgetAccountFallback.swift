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
        let legacy = ProviderCatalog.legacyAccount
        return (legacy.accountID, legacy.displayName)
    }

    /// The account a widget configured for `accountID` shows: that one,
    /// unless it is the legacy sentinel the pickers offered while nothing
    /// was connected and no account has that id, in which case the first
    /// connected account. A first connection on a clean install gets a
    /// UUID, so a widget placed before it would otherwise stay empty
    /// until edited.
    static func resolve(configured accountID: String?, name: String?) -> (accountID: String, accountName: String) {
        if let accountID, let name,
           accountID != ProviderCatalog.legacyAccount.accountID
            || AccountRegistryStore(suiteName: AppConfig.appGroupID)?.account(for: accountID) != nil {
            return (accountID, name)
        }
        return resolve()
    }

    /// The glyph the user picked for this account, from the same registry
    /// the names come from — nil (the default mark) when unset or when the
    /// account is the legacy sentinel.
    static func icon(for accountID: String) -> AccountIcon? {
        AccountRegistryStore(suiteName: AppConfig.appGroupID)?.account(for: accountID)?.icon
    }
}
