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

    static func fetchIfStale(current: UsageSnapshot?, cadence: TimeInterval) async -> UsageSnapshot? {
        if let current, Date().timeIntervalSince(current.fetchedAt) < cadence {
            return nil
        }
        let keychain = KeychainStore(
            service: AppConfig.keychainService,
            accessGroup: AppConfig.keychainAccessGroup
        )
        let provider = ClaudeProvider(
            credentialSource: ClaudeKeychainCredentialSource(store: keychain),
            transport: URLSessionTransport(session: session)
        )
        guard let fetched = try? await provider.fetchUsage() else { return nil }
        let snapshot = fetched.fillingMissingResets(from: current)
        try? SnapshotStore(suiteName: AppConfig.appGroupID)?.save(snapshot)
        // Keep the usage history continuous even when only the widget fetches,
        // so the run-out predictor's recent-rate stays accurate.
        UsageHistoryStore(suiteName: AppConfig.appGroupID)?.record(snapshot)
        return snapshot
    }
}
#endif
