import CryptoKit
import Foundation
import UsageKit

/// A key-value store with iCloud's shape (`NSUbiquitousKeyValueStore`),
/// so the sync is driven by a dictionary in tests.
protocol CloudKeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    var allKeys: [String] { get }
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: CloudKeyValueStore {
    var allKeys: [String] { Array(dictionaryRepresentation.keys) }
}

/// iCloud sync, opt-in (`Preferences.cloudSync`): the display preferences
/// and every connected account's usage history, through the user's own
/// iCloud key-value store, between their iPhone and their Mac. Never the
/// logins. An account is matched across devices by its `syncIdentity`
/// (the login's id from the provider's profile), so the same account
/// connected on both sides shares one history, which merges
/// (`UsageTimeline.merged`) rather than overwrites: each device keeps
/// recording its own samples and both converge on the union. Preferences
/// are one value, newest wins. See "iCloud sync" in the repo-root
/// CLAUDE.md.
@MainActor
final class CloudSync {
    static let prefsKey = "v1.prefs"
    static let historyPrefix = "v1.history."
    /// The store holds 1 MB in all; a month of one account is tens of KB
    /// before compression. A series past this is not sent.
    static let maxValueBytes = 200_000
    /// A sweep lands its accounts one by one; one send per account per
    /// burst.
    static let historyDebounce: Duration = .seconds(20)
    /// When this device's synced preferences last changed, or last took
    /// another device's (App Group defaults): what decides, at launch,
    /// whether the store's are newer than this device's.
    static let prefsStampKey = "cloud.prefsUpdatedAt"

    /// The preferences both devices draw with (never the per-device ones:
    /// appearance, the cadence, the Mac's chrome).
    struct SyncedPreferences: Codable, Equatable {
        var updatedAt: Date
        var displayMode: String
        var resetStyle: String
        var glanceMetric: String
        var modelSlotFallback: String
        var showCreditsAmount: Bool
        var usageColors: Bool

        init(_ prefs: Preferences, updatedAt: Date) {
            self.updatedAt = updatedAt
            displayMode = prefs.displayMode.rawValue
            resetStyle = prefs.resetStyle.rawValue
            glanceMetric = prefs.glanceMetric.storageKey
            modelSlotFallback = prefs.modelSlotFallback.rawValue
            showCreditsAmount = prefs.showCreditsAmount
            usageColors = prefs.usageColors
        }

        /// The same choices, whenever they were made.
        func sameChoices(as other: SyncedPreferences?) -> Bool {
            guard var other else { return false }
            other.updatedAt = updatedAt
            return other == self
        }

        /// Writes the choices through the app's model, so every surface
        /// and the widgets follow; a value this build doesn't know is
        /// left alone.
        func apply(to model: PreferencesModel) {
            if let mode = DisplayMode(rawValue: displayMode) { model.displayMode = mode }
            if let style = ResetStyle(rawValue: resetStyle) { model.resetStyle = style }
            if let metric = UsageWindow.Kind(storageKey: glanceMetric) { model.glanceMetric = metric }
            if let fallback = ModelSlotFallback(rawValue: modelSlotFallback) { model.modelSlotFallback = fallback }
            model.showCreditsAmount = showCreditsAmount
            model.usageColors = usageColors
        }
    }

    /// One account's history as stored: the login it belongs to and
    /// every window's samples, compressed.
    struct HistoryEnvelope: Codable, Equatable {
        var identity: String
        var updatedAt: Date
        var windows: [String: [TimelineSample]]
    }

    private let store: CloudKeyValueStore
    private let timelines: UsageTimelineStore?
    private let registry: AccountRegistryStore?
    private let defaults: UserDefaults
    private var observer: (any NSObjectProtocol)?
    private var pending: [String: Task<Void, Never>] = [:]
    private var lastPushedPrefs: SyncedPreferences?
    private var lastPushedHistory: [String: [String: [TimelineSample]]] = [:]

    /// Another device's history landed for this account (its `accountID`
    /// here): the model reloads what it draws from.
    var onRemoteHistory: ((String) -> Void)?
    /// Another device's preferences, newer than this device's.
    var onRemotePreferences: ((SyncedPreferences) -> Void)?

    init(store: CloudKeyValueStore, timelines: UsageTimelineStore?, registry: AccountRegistryStore?, defaults: UserDefaults) {
        self.store = store
        self.timelines = timelines
        self.registry = registry
        self.defaults = defaults
    }

    private var prefsStamp: Date? {
        get { defaults.object(forKey: Self.prefsStampKey) as? Date }
        set { defaults.set(newValue, forKey: Self.prefsStampKey) }
    }

    /// Watches the store for the other devices' writes, takes what is
    /// already there, and sends this device's own where the store holds
    /// nothing newer: the preferences, and every matched account's
    /// history.
    func start(preferences: Preferences, now: Date = Date()) {
        if observer == nil, let ubiquitous = store as? NSUbiquitousKeyValueStore {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: ubiquitous, queue: .main
            ) { [weak self] notification in
                let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
                let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Another iCloud account signed in: nothing of the
                    // old one applies, start from what the new one holds.
                    if reason == NSUbiquitousKeyValueStoreAccountChange || keys == nil {
                        pullAll()
                    } else {
                        pull(keys: keys ?? [])
                    }
                }
            }
        }
        store.synchronize()
        pullAll()
        if lastPushedPrefs == nil { pushPreferences(preferences, now: now) }
        for account in registry?.accounts() ?? [] where account.syncIdentity != nil {
            pushHistorySoon(for: account)
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        for task in pending.values { task.cancel() }
        pending.removeAll()
        lastPushedPrefs = nil
        lastPushedHistory.removeAll()
    }

    /// The switch going off: AIMeter's keys leave the store. Another
    /// device still syncing sends its own again on its next change.
    func removeAll() {
        for key in store.allKeys where key == Self.prefsKey || key.hasPrefix(Self.historyPrefix) {
            store.set(nil, forKey: key)
        }
        store.synchronize()
        lastPushedPrefs = nil
        lastPushedHistory.removeAll()
    }

    /// An account disconnected here: its history leaves the store with
    /// its file. Another device that still has the login sends its own
    /// again on its next refresh.
    func removeHistory(identity: String) {
        store.set(nil, forKey: Self.key(for: identity))
        store.synchronize()
    }

    // MARK: - Push

    /// Sends the preferences when their choices changed since the last
    /// send (the ones another device sent and this one applied count as
    /// sent, so nothing echoes back).
    func pushPreferences(_ prefs: Preferences, now: Date = Date()) {
        let synced = SyncedPreferences(prefs, updatedAt: now)
        guard !synced.sameChoices(as: lastPushedPrefs) else { return }
        guard let data = try? JSONEncoder().encode(synced) else { return }
        store.set(data, forKey: Self.prefsKey)
        store.synchronize()
        lastPushedPrefs = synced
        prefsStamp = now
    }

    /// Sends this account's history soon, once per burst.
    func pushHistorySoon(for account: ConnectedAccount) {
        pending[account.accountID]?.cancel()
        pending[account.accountID] = Task { [weak self] in
            try? await Task.sleep(for: Self.historyDebounce)
            guard !Task.isCancelled else { return }
            self?.pushHistory(for: account)
        }
    }

    /// Sends this account's history now: the whole compacted series of
    /// every window, under the login's key, unless nothing changed since
    /// the last send or the account's login isn't known yet.
    func pushHistory(for account: ConnectedAccount, now: Date = Date()) {
        guard let identity = account.syncIdentity, let timelines else { return }
        let windows = timelines.allSamples(for: account.accountID)
        guard !windows.isEmpty, windows != lastPushedHistory[account.accountID] else { return }
        let envelope = HistoryEnvelope(identity: identity, updatedAt: now, windows: windows)
        guard let data = try? Self.encode(envelope), data.count <= Self.maxValueBytes else { return }
        store.set(data, forKey: Self.key(for: identity))
        store.synchronize()
        lastPushedHistory[account.accountID] = windows
    }

    // MARK: - Pull

    func pullAll() {
        pull(keys: store.allKeys)
    }

    func pull(keys: [String]) {
        for key in keys {
            if key == Self.prefsKey {
                pullPreferences()
            } else if key.hasPrefix(Self.historyPrefix) {
                pullHistory(key: key)
            }
        }
    }

    private func pullPreferences() {
        guard let data = store.data(forKey: Self.prefsKey),
              let remote = try? JSONDecoder().decode(SyncedPreferences.self, from: data) else { return }
        if let stamp = prefsStamp {
            // Older than this device's own change: this device's stand,
            // and go out on their next send.
            if remote.updatedAt < stamp { return }
            // The very ones this device sent or took.
            if remote.updatedAt == stamp { lastPushedPrefs = remote; return }
        }
        lastPushedPrefs = remote
        prefsStamp = remote.updatedAt
        onRemotePreferences?(remote)
    }

    private func pullHistory(key: String) {
        guard let data = store.data(forKey: key), let envelope = try? Self.decode(data),
              Self.key(for: envelope.identity) == key,
              let account = registry?.accounts().first(where: { $0.syncIdentity == envelope.identity }),
              let timelines else { return }
        guard timelines.merge(envelope.windows, for: account.accountID) else {
            // Nothing new here. The same series on both sides is in sync;
            // a store holding less than this device is sent this one's.
            if envelope.windows == timelines.allSamples(for: account.accountID) {
                lastPushedHistory[account.accountID] = envelope.windows
            }
            return
        }
        onRemoteHistory?(account.accountID)
        // What this device holds now is more than the store's; send it.
        pushHistorySoon(for: account)
    }

    // MARK: - Keys and encoding

    /// The store's key for a login: a digest, so the id itself is not the
    /// key's text.
    static func key(for identity: String) -> String {
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return historyPrefix + digest.prefix(32)
    }

    static func encode(_ envelope: HistoryEnvelope) throws -> Data {
        let json = try JSONEncoder().encode(envelope)
        return try (json as NSData).compressed(using: .zlib) as Data
    }

    static func decode(_ data: Data) throws -> HistoryEnvelope {
        let json = try (data as NSData).decompressed(using: .zlib) as Data
        return try JSONDecoder().decode(HistoryEnvelope.self, from: json)
    }
}
