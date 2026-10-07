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
    /// The glyph the user picked for this account, or nil for the app's
    /// default mark. Optional and absent from any registry written before
    /// it existed, so an upgrade decodes unchanged.
    public var icon: AccountIcon?

    public init(
        accountID: String,
        providerID: String,
        displayName: String,
        credentialStrategy: CredentialStrategy,
        connectedAt: Date = Date(),
        icon: AccountIcon? = nil
    ) {
        self.accountID = accountID
        self.providerID = providerID
        self.displayName = displayName
        self.credentialStrategy = credentialStrategy
        self.connectedAt = connectedAt
        self.icon = icon
    }
}

/// What an account's header glyph shows: an SF Symbol by name, or one of
/// the bundled marks. Pure data — the drawing is the app's
/// (`ProviderMark`), and the widget extension reads it from the registry
/// like every other account field. Encoded as `{"kind": …, "value": …}`
/// so the stored form stays readable and a future kind can't collide with
/// the synthesized associated-value layout.
public enum AccountIcon: Codable, Hashable, Sendable {
    /// An SF Symbol, by its system name ("bolt.fill").
    case symbol(String)
    /// One of the marks shipped in the app's asset catalog.
    case mark(Mark)

    public enum Mark: String, Codable, Hashable, Sendable, CaseIterable {
        case claude
        case claudeCode
    }

    private enum CodingKeys: String, CodingKey { case kind, value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let value = try container.decode(String.self, forKey: .value)
        switch kind {
        case "symbol":
            self = .symbol(value)
        case "mark":
            guard let mark = Mark(rawValue: value) else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "unknown mark \(value)")
            }
            self = .mark(mark)
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown icon kind \(kind)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .symbol(let name):
            try container.encode("symbol", forKey: .kind)
            try container.encode(name, forKey: .value)
        case .mark(let mark):
            try container.encode("mark", forKey: .kind)
            try container.encode(mark.rawValue, forKey: .value)
        }
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
public struct AccountRegistryStore: @unchecked Sendable {
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

    /// Sets or clears (nil) the account's chosen glyph. Like `rename`, a
    /// change to how the account is *shown*, never to what it is.
    public func setIcon(_ icon: AccountIcon?, for accountID: String) {
        var current = accounts()
        guard let index = current.firstIndex(where: { $0.accountID == accountID }) else { return }
        current[index].icon = icon
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
