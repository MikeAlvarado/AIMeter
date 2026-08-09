#if os(iOS)
import Foundation
import UsageKit

/// Lets the widget process fetch usage itself when the stored snapshot is
/// older than the refresh cadence — the case where the app hasn't been
/// opened and iOS didn't grant its background task. Credentials come from
/// the shared keychain access group; ClaudeProvider refreshes an expired
/// token in place, so the widget stays live for days without the app.
/// On failure the caller keeps rendering the stored snapshot.
enum WidgetRefresher {
    /// Short-timeout session for widget fetches: a timeline is generated on
    /// a tight budget, so a slow request must fail fast rather than stall
    /// (and waste the refresh) waiting on `URLSession.shared`'s 60s default.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Guards a user-initiated `refreshNow` against a double-tap or button
    /// mashing — deliberately much shorter than `AppConfig.widgetRefreshFloor`
    /// (30 min), which protects WidgetKit's *background* refresh budget. A
    /// direct tap is high-priority and user-initiated, not subject to that
    /// same budget throttling, so this is just spam protection, not a real
    /// staleness check.
    private static let minInterval: TimeInterval = 5

    static func fetchIfStale(
        accountID: String,
        current: UsageSnapshot?,
        cadence: TimeInterval
    ) async -> UsageSnapshot? {
        if let current, Date().timeIntervalSince(current.fetchedAt) < cadence {
            return nil
        }
        return await fetch(accountID: accountID, previous: current)
    }

    /// Unconditional (modulo the anti-spam floor above) fetch for an
    /// interactive widget button tap — as opposed to `fetchIfStale`'s
    /// passive check during timeline generation.
    static func refreshNow(accountID: String) async -> UsageSnapshot? {
        let current = SnapshotStore(suiteName: AppConfig.appGroupID)?.snapshot(for: accountID)
        if let current, Date().timeIntervalSince(current.fetchedAt) < minInterval {
            return nil
        }
        return await fetch(accountID: accountID, previous: current)
    }

    private static func fetch(accountID: String, previous: UsageSnapshot?) async -> UsageSnapshot? {
        let keychain = KeychainStore(
            service: AppConfig.keychainService,
            accessGroup: AppConfig.keychainAccessGroup
        )
        let credentialKey = ClaudeKeychainCredentialSource.storageKey(for: accountID)
        let provider = ClaudeProvider(
            credentialSource: ClaudeKeychainCredentialSource(store: keychain, key: credentialKey),
            transport: URLSessionTransport(session: session)
        )
        guard let fetched = try? await provider.fetchUsage() else { return nil }
        let snapshot = fetched.fillingMissingResets(from: previous)
        try? SnapshotStore(suiteName: AppConfig.appGroupID)?.save(snapshot, for: accountID)
        // Keep the usage history continuous even when only the widget fetches,
        // so the run-out predictor's recent-rate stays accurate.
        UsageHistoryStore(suiteName: AppConfig.appGroupID)?.record(snapshot, for: accountID)
        // Same reasoning as the history record above: a running Live
        // Activity should stay fresh even on cycles where only the widget
        // (not the app) fetches. No-op when the account's toggle is off.
        let accountName = AccountRegistryStore(suiteName: AppConfig.appGroupID)?.account(for: accountID)?.displayName ?? "Claude"
        LiveActivityManager.sync(
            accountID: accountID, accountName: accountName, snapshot: snapshot,
            enabled: LiveActivityPreferences(accountID: accountID).enabled
        )
        return snapshot
    }
}
#endif
