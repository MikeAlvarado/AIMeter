import Foundation
import WidgetKit
import UsageKit

/// The outcome of refreshing one provider: either a new snapshot, or an
/// error to surface for that provider specifically — one provider failing
/// must not blank the others sharing this refresh cycle.
struct ProviderRefreshResult {
    let providerID: String
    let snapshot: UsageSnapshot?
    let error: Error?
}

/// Fetches usage from every known provider, persists each snapshot to the
/// App Group, reloads widget timelines once, and reschedules each
/// provider's own notifications. Used by the UI, the iOS background task,
/// and the macOS refresh timer.
struct RefreshService {
    private let claudeProvider: ClaudeProvider
    private let claudeCredentialSource: any ClaudeCredentialSource
    private let store: SnapshotStore?
    private let historyStore: UsageHistoryStore?

    init() {
        Self.migrateCredentialsToSharedGroup()
        Self.migrateNotificationKeysToProviderScope()
        #if os(macOS)
        claudeCredentialSource = ClaudeAutoCredentialSource(store: Self.keychainStore)
        #else
        claudeCredentialSource = ClaudeKeychainCredentialSource(store: Self.keychainStore)
        #endif
        claudeProvider = ClaudeProvider(credentialSource: claudeCredentialSource)
        store = SnapshotStore(suiteName: AppConfig.appGroupID)
        historyStore = UsageHistoryStore(suiteName: AppConfig.appGroupID)
    }

    /// Every provider fetched together on each refresh. One entry today;
    /// this is the seam a second provider plugs into — the concurrency,
    /// per-provider error isolation, and notification scoping below are
    /// already written for N, not additively bolted on later.
    private var providers: [any UsageProvider] { [claudeProvider] }

    private static var keychainStore: KeychainStore {
        KeychainStore(service: AppConfig.keychainService, accessGroup: AppConfig.keychainAccessGroup)
    }

    /// One-time move of credentials saved before keychain sharing into the
    /// shared access group, so the widget extension can read them too.
    private static func migrateCredentialsToSharedGroup() {
        guard AppConfig.keychainAccessGroup != nil else { return }
        let legacy = KeychainStore(service: AppConfig.keychainService)
        let key = ClaudeKeychainCredentialSource.defaultKey
        guard (try? keychainStore.data(for: key)) == nil,
              let data = try? legacy.data(for: key), !data.isEmpty else { return }
        try? legacy.delete(key)
        try? keychainStore.set(data, for: key)
    }

    /// One-time rewrite of pre-multi-provider notification toggle keys
    /// (`"notify.<kind>"`) to the provider-scoped format
    /// (`"notify.claude.<kind>"`) `NotificationPreferences` now uses. Any
    /// pre-existing key is unambiguously Claude's — it's the only provider
    /// that has ever existed. The five global smart-notification keys
    /// (`notify.runout`, `notify.earlyReset`, `notify.nearLimit`,
    /// `notify.nearLimitThreshold`, `notify.limitReached`) aren't
    /// per-window and were never in this format — skipped naturally since
    /// their key suffix doesn't round-trip through
    /// `UsageWindow.Kind(storageKey:)`. Idempotent, guarded by a completed
    /// flag so it only ever scans once.
    ///
    /// Internal (not private) and takes an injectable `defaults` so
    /// `AIMeterTests` can exercise it against an isolated suite instead of
    /// the real App Group.
    static func migrateNotificationKeysToProviderScope(
        defaults: UserDefaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    ) {
        let flag = "migration.notificationKeysProviderScoped"
        guard !defaults.bool(forKey: flag) else { return }

        for (key, value) in defaults.dictionaryRepresentation() {
            guard key.hasPrefix("notify."), !key.hasPrefix("notify.claude."),
                  let enabled = value as? Bool else { continue }
            let suffix = String(key.dropFirst("notify.".count))
            guard UsageWindow.Kind(storageKey: suffix) != nil else { continue }
            defaults.set(enabled, forKey: "notify.claude.\(suffix)")
        }
        defaults.set(true, forKey: flag)
    }

    func lastSnapshot(for providerID: String) -> UsageSnapshot? {
        store?.snapshot(for: providerID)
    }

    /// When usage history first started recording — the pace warm-up anchor.
    func paceObservingSince(for providerID: String) -> Date? {
        historyStore?.observingSince(for: providerID)
    }

    /// Fetches every provider concurrently and returns one result each —
    /// a failure in one provider's fetch doesn't affect the others'
    /// results. Widget timelines reload once, after every provider settles.
    @discardableResult
    func refresh() async -> [ProviderRefreshResult] {
        let results = await withTaskGroup(of: ProviderRefreshResult.self) { group -> [ProviderRefreshResult] in
            for provider in providers {
                group.addTask { await refreshOne(provider) }
            }
            var results: [ProviderRefreshResult] = []
            for await result in group { results.append(result) }
            return results
        }
        WidgetCenter.shared.reloadAllTimelines()
        return results
    }

    private func refreshOne(_ provider: any UsageProvider) async -> ProviderRefreshResult {
        let previous = store?.snapshot(for: provider.id)
        do {
            let snapshot = try await provider.fetchUsage().fillingMissingResets(from: previous)
            try store?.save(snapshot)
            historyStore?.record(snapshot)

            let prefs = NotificationPreferences()
            await NotificationScheduler.rescheduleResets(for: snapshot, providerID: provider.id, preferences: prefs)
            await NotificationScheduler.rescheduleRunOuts(
                runOutProjections(for: snapshot), providerID: provider.id, preferences: prefs
            )
            if let previous {
                await fireDetectionAlerts(previous: previous, current: snapshot, preferences: prefs)
            }
            return ProviderRefreshResult(providerID: provider.id, snapshot: snapshot, error: nil)
        } catch is CancellationError {
            // A superseded refresh (pull-to-refresh released, scene change)
            // is not an error worth showing.
            return ProviderRefreshResult(providerID: provider.id, snapshot: nil, error: nil)
        } catch let error as URLError where error.code == .cancelled {
            return ProviderRefreshResult(providerID: provider.id, snapshot: nil, error: nil)
        } catch {
            return ProviderRefreshResult(providerID: provider.id, snapshot: nil, error: error)
        }
    }

    /// Immediate, detection-based alerts (compare previous vs new): early
    /// refill, hitting the limit, and nearing it. A single big jump can
    /// cross both the near-limit threshold and the limit — the more severe
    /// "limit reached" wins, so its kinds are excluded from the near-limit
    /// set to avoid a double notification.
    private func fireDetectionAlerts(
        previous: UsageSnapshot,
        current: UsageSnapshot,
        preferences prefs: NotificationPreferences
    ) async {
        await NotificationScheduler.notifyEarlyResets(
            ResetDetector.earlyResets(previous: previous, current: current),
            providerID: current.providerID,
            preferences: prefs
        )

        let reached = ThresholdDetector.crossedUp(
            previous: previous, current: current,
            threshold: ThresholdDetector.limitReachedThreshold
        )
        await NotificationScheduler.notifyLimitReached(reached, in: current, preferences: prefs)

        let nearing = ThresholdDetector.crossedUp(
            previous: previous, current: current,
            threshold: prefs.nearLimitThreshold
        ).filter { !reached.contains($0) }
        await NotificationScheduler.notifyNearLimit(nearing, in: current, preferences: prefs)
    }

    /// Run-out projections for alerts: recent-rate from history when there's
    /// enough signal, otherwise the average rate (gated by a minimum used%
    /// so a barely-touched window doesn't warn). Empty before any usage.
    private func runOutProjections(for snapshot: UsageSnapshot) -> [UsageWindow.Kind: RunOutProjection] {
        var result: [UsageWindow.Kind: RunOutProjection] = [:]
        for window in snapshot.windows {
            let samples = historyStore?.samples(for: snapshot.providerID, kind: window.kind) ?? []
            if let recent = RunOutPredictor.recentProjection(for: window, samples: samples) {
                result[window.kind] = recent
            } else if let average = RunOutPredictor.averageProjection(
                for: window, minimumUsedPct: RunOutPredictor.alertMinimumUsedPct
            ) {
                result[window.kind] = average
            }
        }
        return result
    }

    // MARK: - Connection management (Claude's in-app OAuth flow)

    static func storedCredentialsExist() -> Bool {
        (try? keychainStore.data(for: ClaudeKeychainCredentialSource.defaultKey)) != nil
    }

    func storeConnection(_ credentials: ClaudeCredentials) async throws {
        try await claudeCredentialSource.save(credentials)
    }

    func disconnect() throws {
        #if os(macOS)
        try (claudeCredentialSource as? ClaudeAutoCredentialSource)?.clear()
        #else
        try (claudeCredentialSource as? ClaudeKeychainCredentialSource)?.clear()
        #endif
        store?.removeSnapshot(for: claudeProvider.id)
        historyStore?.clear(for: claudeProvider.id)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
