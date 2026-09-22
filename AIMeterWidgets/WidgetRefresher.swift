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

    /// How long an in-flight marker suppresses other instances' fetches
    /// for the same account — comfortably longer than the 15 s request
    /// timeout, short enough that a crashed extension can't block for long.
    private static let inFlightWindow: TimeInterval = 60

    static func fetchIfStale(
        accountID: String,
        current: UsageSnapshot?,
        cadence: TimeInterval
    ) async -> UsageSnapshot? {
        if let current, Date().timeIntervalSince(current.fetchedAt) < cadence {
            return nil
        }
        // Every placed instance runs its own timeline in the same reload
        // burst, so three widgets for one account would otherwise be three
        // identical fetches (and three refresh-token rotations). Re-read the
        // store first — another instance may have just saved — then claim
        // the fetch with an in-flight stamp the others back off from.
        let store = SnapshotStore(suiteName: AppConfig.appGroupID)
        if let latest = store?.snapshot(for: accountID),
           Date().timeIntervalSince(latest.fetchedAt) < cadence {
            return latest
        }
        let defaults = UserDefaults(suiteName: AppConfig.appGroupID)
        let stampKey = "widget.fetchInFlight.\(accountID)"
        if let started = defaults?.object(forKey: stampKey) as? Date,
           Date().timeIntervalSince(started) < inFlightWindow {
            return nil
        }
        defaults?.set(Date(), forKey: stampKey)
        defer { defaults?.removeObject(forKey: stampKey) }
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
        // The registry says which provider this account is; an id the
        // registry doesn't know (the legacy fallback before migration) is
        // the default provider's.
        let account = AccountRegistryStore(suiteName: AppConfig.appGroupID)?.account(for: accountID)
            ?? ProviderCatalog.legacyAccount
        let provider = ProviderCatalog.makeProvider(
            for: account, keychain: keychain, transport: URLSessionTransport(session: session)
        ).provider
        guard let fetched = try? await provider.fetchUsage() else { return nil }
        let snapshot = fetched.fillingMissingResets(from: previous)
        try? SnapshotStore(suiteName: AppConfig.appGroupID)?.save(snapshot, for: accountID)
        // Keep the usage history continuous even when only the widget fetches,
        // so the run-out predictor's recent-rate stays accurate.
        UsageHistoryStore(suiteName: AppConfig.appGroupID)?.record(snapshot, for: accountID)
        // Deliberately no Live Activity sync here: ActivityKit only exposes
        // (and lets you update) activities from the app process, so the
        // extension can't keep one fresh — the app's own next fetch does.
        return snapshot
    }
}
#endif
