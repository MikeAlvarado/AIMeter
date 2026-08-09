import AppIntents
import UsageKit

/// One selectable (account, window kind) pair for the single-limit widget's
/// Edit Widget UI. Options are read from each connected account's last
/// stored snapshot so the list always matches what that account actually
/// reports right now — e.g. a Pro account with no per-model window simply
/// offers session and weekly, rather than a name baked in at build time.
struct UsageWindowOption: AppEntity {
    let accountID: String
    let kind: UsageWindow.Kind
    let accountName: String

    var id: String { "\(accountID)|\(kind.storageKey)" }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Usage Window"
    static var defaultQuery = UsageWindowOptionQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(accountName) · \(kind.shortName)")
    }

    init(accountID: String, kind: UsageWindow.Kind, accountName: String) {
        self.accountID = accountID
        self.kind = kind
        self.accountName = accountName
    }

    /// Reconstructs an option straight from its persisted `id`, so a
    /// previously chosen window still resolves even if it's since dropped
    /// out of the account's current snapshot (e.g. a plan change removed
    /// it) — the widget then simply has nothing to show for it, rather
    /// than silently reverting to a different selection.
    init?(id: String) {
        let parts = id.split(separator: "|", maxSplits: 1)
        guard parts.count == 2, let kind = UsageWindow.Kind(storageKey: String(parts[1])) else {
            return nil
        }
        let accountID = String(parts[0])
        self.init(accountID: accountID, kind: kind, accountName: Self.accountName(for: accountID))
    }

    /// Looks up the account's nickname from the shared registry. Falls back
    /// to "Claude" for the legacy id or a registry that hasn't loaded yet
    /// (e.g. the widget process running before the app has ever migrated).
    static func accountName(for accountID: String) -> String {
        AccountRegistryStore(suiteName: AppConfig.appGroupID)?.account(for: accountID)?.displayName
            ?? (accountID == ClaudeKeychainCredentialSource.legacyAccountID ? "Claude" : accountID)
    }
}

struct UsageWindowOptionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [UsageWindowOption] {
        identifiers.compactMap(UsageWindowOption.init(id:))
    }

    func suggestedEntities() async throws -> [UsageWindowOption] {
        currentOptions()
    }

    func defaultResult() async -> UsageWindowOption? {
        currentOptions().first
    }

    /// Enumerates every connected account's live windows — an account with
    /// no per-model window and the credits fallback actually showing
    /// (Settings: Credits, or Auto with credits enabled) also offers
    /// "Credits", same rule `WindowSlots` uses for the dashboard's third
    /// slot. An empty registry (nothing connected yet, or the app hasn't
    /// run its one-time account migration since this install's last
    /// update) falls back to the single legacy "claude" identity rather
    /// than an empty picker.
    private func currentOptions() -> [UsageWindowOption] {
        let registry = AccountRegistryStore(suiteName: AppConfig.appGroupID)
        let store = SnapshotStore(suiteName: AppConfig.appGroupID)
        let accounts = registry?.accounts() ?? []
        let resolved = accounts.isEmpty
            ? [ConnectedAccount(accountID: ClaudeKeychainCredentialSource.legacyAccountID, providerID: "claude", displayName: "Claude", credentialStrategy: .managed)]
            : accounts

        return resolved.flatMap { account -> [UsageWindowOption] in
            let snapshot = store?.snapshot(for: account.accountID)
            let kinds = snapshot?.windows.map(\.kind) ?? []
            var resolvedKinds = kinds.isEmpty ? [.session, .weekly] : kinds

            let hasModelWindow = resolvedKinds.contains {
                if case .modelSpecific = $0 { return true }
                return false
            }
            let fallback = Preferences.load().modelSlotFallback
            if !hasModelWindow, fallback != .hidden, snapshot?.creditsWindow != nil {
                resolvedKinds.append(.credits)
            }

            return resolvedKinds.map {
                UsageWindowOption(accountID: account.accountID, kind: $0, accountName: account.displayName)
            }
        }
    }
}

struct SingleUsageConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Usage Window"
    static var description = IntentDescription("Choose which account and limit this widget shows.")

    @Parameter(title: "Limit")
    var window: UsageWindowOption?
}
