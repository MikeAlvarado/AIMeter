import AppIntents
import UsageKit

/// One connected account, for the intents that act on one (Shortcuts and
/// Siri pick it by its nickname). Read from the registry, in its order.
struct AccountEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static var defaultQuery = AccountEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct AccountEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        Self.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        Self.all()
    }

    private static func all() -> [AccountEntity] {
        (AccountRegistryStore(suiteName: AppConfig.appGroupID)?.accounts() ?? [])
            .map { AccountEntity(id: $0.accountID, name: $0.displayName) }
    }
}

/// "How much of Work have I used?": each of one account's windows, after
/// fetching what went stale.
struct AccountUsageIntent: AppIntent {
    static var title: LocalizedStringResource = "Account Usage"
    static var description = IntentDescription("Says how much of each limit one account has used.")

    @Parameter(title: "Account") var account: AccountEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = AppEnvironment.shared else {
            return .result(dialog: "AIMeter isn't running.")
        }
        await model.refreshAllIfStale()
        return .result(dialog: IntentDialog(stringLiteral: UsageSummary.figures(accountID: account.id, in: model)))
    }
}

/// "When does Work reset?": when each of one account's windows refills.
struct NextResetsIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Resets"
    static var description = IntentDescription("Says when each of one account's limits resets.")

    @Parameter(title: "Account") var account: AccountEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = AppEnvironment.shared else {
            return .result(dialog: "AIMeter isn't running.")
        }
        await model.refreshAllIfStale()
        return .result(dialog: IntentDialog(stringLiteral: UsageSummary.resets(accountID: account.id, in: model)))
    }
}

/// Opens one account's detail.
struct OpenAccountIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Account"
    static var description = IntentDescription("Opens one account's details in AIMeter.")
    static var openAppWhenRun = true

    @Parameter(title: "Account") var account: AccountEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        #if os(macOS)
        AppChrome.openAccount(account.id)
        #else
        AppEnvironment.shared?.accountToOpen = account.id
        #endif
        return .result()
    }
}
