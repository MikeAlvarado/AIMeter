import Foundation
import UsageKit

/// What the iPhone sends the Watch (`WatchBridge`) and the Watch keeps
/// (`WatchStore`): the accounts in the Dashboard's order, each with its
/// last snapshot, and the preferences the Watch draws with. One JSON blob
/// under `key` in the WatchConnectivity dictionary, the version beside
/// it, so a Watch app older than the phone's can tell what it was sent;
/// fields it doesn't know are ignored. Whole, never a delta:
/// `updateApplicationContext` keeps only the last value, and the Watch
/// may have missed any number in between.
nonisolated struct WatchPayload: Codable, Equatable, Sendable {
    static let version = 1
    static let key = "payload"
    static let versionKey = "version"
    /// The one message the Watch sends: a refresh request, answered with
    /// a payload.
    static let refreshKey = "refresh"
    /// When the Watch last received a payload, in its own App Group.
    static let receivedAtKey = "watch.receivedAt"

    struct Account: Codable, Equatable, Sendable {
        let accountID: String
        let providerID: String
        let displayName: String
        var icon: AccountIcon?
        var snapshot: UsageSnapshot?
    }

    /// The display preferences, by raw value: the Watch stores them under
    /// the phone's own keys and reads them back with `Preferences.load`.
    struct Prefs: Codable, Equatable, Sendable {
        var displayMode: String
        var resetStyle: String
        var glanceMetric: String
        var modelSlotFallback: String
        var showCreditsAmount: Bool
        var usageColors: Bool

        init(_ prefs: Preferences) {
            displayMode = prefs.displayMode.rawValue
            resetStyle = prefs.resetStyle.rawValue
            glanceMetric = prefs.glanceMetric.storageKey
            modelSlotFallback = prefs.modelSlotFallback.rawValue
            showCreditsAmount = prefs.showCreditsAmount
            usageColors = prefs.usageColors
        }
    }

    var sentAt: Date
    var accounts: [Account]
    var prefs: Prefs

    init(sentAt: Date = Date(), accounts: [Account], prefs: Prefs) {
        self.sentAt = sentAt
        self.accounts = accounts
        self.prefs = prefs
    }

    // MARK: - The WatchConnectivity dictionary

    func contextDictionary() throws -> [String: Any] {
        [Self.key: try JSONEncoder().encode(self), Self.versionKey: Self.version]
    }

    /// nil for a dictionary without a payload, or one this build can't
    /// read.
    init?(context: [String: Any]) {
        guard let data = context[Self.key] as? Data,
              let decoded = try? JSONDecoder().decode(WatchPayload.self, from: data) else { return nil }
        self = decoded
    }

    // MARK: - The Watch's stores

    /// Everything into the Watch's own App Group, where its views and
    /// complications read it the way the phone's widgets read theirs: the
    /// registry replaced in this order, each account's snapshot saved (or
    /// removed, with those of accounts no longer sent), the preferences
    /// under their keys.
    func apply(registry: AccountRegistryStore, snapshots: SnapshotStore, defaults: UserDefaults) {
        let before = Set(registry.accounts().map(\.accountID))
        registry.replaceAll(accounts.map { account in
            ConnectedAccount(
                accountID: account.accountID, providerID: account.providerID,
                displayName: account.displayName, credentialStrategy: .managed, icon: account.icon
            )
        })
        for account in accounts {
            if let snapshot = account.snapshot {
                try? snapshots.save(snapshot, for: account.accountID)
            } else {
                snapshots.removeSnapshot(for: account.accountID)
            }
        }
        for gone in before.subtracting(accounts.map(\.accountID)) {
            snapshots.removeSnapshot(for: gone)
        }
        defaults.set(prefs.displayMode, forKey: Preferences.Keys.displayMode)
        defaults.set(prefs.resetStyle, forKey: Preferences.Keys.resetStyle)
        defaults.set(prefs.glanceMetric, forKey: Preferences.Keys.glanceMetric)
        defaults.set(prefs.modelSlotFallback, forKey: Preferences.Keys.modelSlotFallback)
        defaults.set(prefs.showCreditsAmount, forKey: Preferences.Keys.showCreditsAmount)
        defaults.set(prefs.usageColors, forKey: Preferences.Keys.usageColors)
        defaults.set(sentAt, forKey: Self.receivedAtKey)
    }
}
