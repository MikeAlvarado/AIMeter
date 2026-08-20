import Foundation

/// One specific connected login. Distinct from `UsageProvider.id`/
/// `UsageSnapshot.providerID`, which identify the provider *family* (e.g.
/// "claude") — `accountID` identifies one specific login of that family,
/// and is the key actually used by SnapshotStore, UsageHistoryStore,
/// Keychain, notifications, and widget account selection.
public struct ConnectedAccount: Codable, Hashable, Sendable, Identifiable {
    public enum CredentialStrategy: String, Codable, Sendable {
        /// Credentials the app owns in its own Keychain item (in-app OAuth
        /// or a pasted credentials JSON).
        case managed
        /// macOS only: mirrors Claude Code CLI's own login. Read-only,
        /// never refreshed by AIMeter, and capped at one account per
        /// machine since the CLI itself only tracks one login.
        case autoDetected
    }

    public var id: String { accountID }
    public let accountID: String
    public let providerID: String
    public var displayName: String
    public var credentialStrategy: CredentialStrategy
    public var connectedAt: Date

    public init(
        accountID: String,
        providerID: String,
        displayName: String,
        credentialStrategy: CredentialStrategy,
        connectedAt: Date = Date()
    ) {
        self.accountID = accountID
        self.providerID = providerID
        self.displayName = displayName
        self.credentialStrategy = credentialStrategy
        self.connectedAt = connectedAt
    }
}

/// The list of currently connected accounts, in display order — the App
/// Group-shared source of truth the Dashboard, menu bar, and widget
/// `AppIntent` option queries all enumerate from. Only the app calls the
/// mutating methods; the widget extension only ever reads via
/// `accounts()`/`account(for:)`, mirroring `SnapshotStore`'s "only the app
/// writes" contract. `remove` is deliberately non-cascading — it doesn't
/// touch Keychain/Snapshot/History/notifications for that account; that
/// orchestration belongs to the app layer.
public struct AccountRegistryStore: Sendable {
    private let defaults: UserDefaults
    private static let key = "usage.accounts"

    /// - Parameter suiteName: the App Group identifier,
    ///   e.g. "group.com.mikealvarado.aimeter". Returns nil if the suite
    ///   cannot be opened (missing entitlement).
    public init?(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return nil
        }
        self.defaults = defaults
    }

    public init(userDefaults: UserDefaults) {
        self.defaults = userDefaults
    }

    public func accounts() -> [ConnectedAccount] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ConnectedAccount].self, from: data)) ?? []
    }

    public func account(for accountID: String) -> ConnectedAccount? {
        accounts().first { $0.accountID == accountID }
    }

    @discardableResult
    public func add(_ account: ConnectedAccount) -> Bool {
        var current = accounts()
        guard !current.contains(where: { $0.accountID == account.accountID }) else {
            return false
        }
        current.append(account)
        save(current)
        return true
    }

    public func rename(_ accountID: String, to displayName: String) {
        var current = accounts()
        guard let index = current.firstIndex(where: { $0.accountID == accountID }) else { return }
        current[index].displayName = displayName
        save(current)
    }

    /// Re-points an account at a different credential strategy. The one
    /// real transition is macOS's `.autoDetected` → `.managed`: an account
    /// that mirrored Claude Code's login and then got its own credentials
    /// through the in-app sign-in flow. It happens *because* the CLI-mirrored
    /// login stopped working, and it's one-way — the app now owns a token
    /// pair of its own, so it may refresh it without rotating the CLI's out
    /// from under it.
    public func setCredentialStrategy(_ strategy: ConnectedAccount.CredentialStrategy, for accountID: String) {
        var current = accounts()
        guard let index = current.firstIndex(where: { $0.accountID == accountID }) else { return }
        current[index].credentialStrategy = strategy
        save(current)
    }

    public func remove(_ accountID: String) {
        save(accounts().filter { $0.accountID != accountID })
    }

    /// Rewrites the whole list, order included — the app's dashboard uses
    /// this to persist a drag-reorder, since this list's order *is* the
    /// display order every surface enumerates (dashboard, menu bar popover,
    /// all-accounts widget, and the widget account pickers).
    public func replaceAll(_ accounts: [ConnectedAccount]) {
        save(accounts)
    }

    private func save(_ accounts: [ConnectedAccount]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(accounts) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
