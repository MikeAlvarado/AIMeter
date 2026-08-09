import AppIntents
import UsageKit

/// One connected account, selectable for the 3-window widget's Edit Widget
/// UI — unlike `UsageWindowOption`, this has no window dimension: the
/// 3-window widget always shows all three windows, just for whichever
/// account is picked here.
struct UsageAccountOption: AppEntity {
    let accountID: String
    let accountName: String

    var id: String { accountID }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Claude Account"
    static var defaultQuery = UsageAccountOptionQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(accountName)")
    }
}

struct UsageAccountOptionQuery: EntityQuery {
    /// Every id resolves (falling back to "Claude" for the legacy id via
    /// `accountName(for:)`), matching `UsageWindowOption`'s tolerance for a
    /// previously-picked account that's since been removed.
    func entities(for identifiers: [String]) async throws -> [UsageAccountOption] {
        identifiers.map { accountID in
            UsageAccountOption(accountID: accountID, accountName: UsageWindowOption.accountName(for: accountID))
        }
    }

    func suggestedEntities() async throws -> [UsageAccountOption] {
        currentOptions()
    }

    func defaultResult() async -> UsageAccountOption? {
        currentOptions().first
    }

    /// Falls back to the single legacy "claude" identity when nothing is
    /// registered yet — same empty-registry contract as
    /// `UsageWindowOptionQuery`.
    private func currentOptions() -> [UsageAccountOption] {
        let accounts = AccountRegistryStore(suiteName: AppConfig.appGroupID)?.accounts() ?? []
        if accounts.isEmpty {
            return [UsageAccountOption(accountID: ClaudeKeychainCredentialSource.legacyAccountID, accountName: "Claude")]
        }
        return accounts.map { UsageAccountOption(accountID: $0.accountID, accountName: $0.displayName) }
    }
}

struct UsageAccountConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Claude Account"
    static var description = IntentDescription("Choose which connected account this widget shows.")

    @Parameter(title: "Account")
    var account: UsageAccountOption?
}
