import Foundation
import WidgetKit
import UsageKit

/// Fetches usage from the provider, persists the snapshot to the App Group,
/// reloads widget timelines, and reschedules reset notifications. Used by
/// the UI, the iOS background task, and the macOS refresh timer.
struct RefreshService {
    let provider: ClaudeProvider
    let credentialSource: any ClaudeCredentialSource
    private let store: SnapshotStore?
    private let historyStore: UsageHistoryStore?

    init() {
        Self.migrateCredentialsToSharedGroup()
        #if os(macOS)
        credentialSource = ClaudeAutoCredentialSource(store: Self.keychainStore)
        #else
        credentialSource = ClaudeKeychainCredentialSource(store: Self.keychainStore)
        #endif
        provider = ClaudeProvider(credentialSource: credentialSource)
        store = SnapshotStore(suiteName: AppConfig.appGroupID)
        historyStore = UsageHistoryStore(suiteName: AppConfig.appGroupID)
    }

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

    func lastSnapshot() -> UsageSnapshot? {
        store?.snapshot(for: provider.id)
    }

    /// When usage history first started recording — the pace warm-up anchor.
    func paceObservingSince() -> Date? {
        historyStore?.observingSince(for: provider.id)
    }

    @discardableResult
    func refresh() async throws -> UsageSnapshot {
        let previous = store?.snapshot(for: provider.id)
        let snapshot = try await provider.fetchUsage()
            .fillingMissingResets(from: previous)
        try store?.save(snapshot)
        historyStore?.record(snapshot)
        WidgetCenter.shared.reloadAllTimelines()

        let prefs = NotificationPreferences()
        await NotificationScheduler.rescheduleResets(for: snapshot, preferences: prefs)
        await NotificationScheduler.rescheduleRunOuts(runOutProjections(for: snapshot), preferences: prefs)
        if let previous {
            await fireDetectionAlerts(previous: previous, current: snapshot, preferences: prefs)
        }
        return snapshot
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

    // MARK: - Connection management (in-app OAuth flow)

    static func storedCredentialsExist() -> Bool {
        (try? keychainStore.data(for: ClaudeKeychainCredentialSource.defaultKey)) != nil
    }

    func storeConnection(_ credentials: ClaudeCredentials) async throws {
        try await credentialSource.save(credentials)
    }

    func disconnect() throws {
        #if os(macOS)
        try (credentialSource as? ClaudeAutoCredentialSource)?.clear()
        #else
        try (credentialSource as? ClaudeKeychainCredentialSource)?.clear()
        #endif
        store?.removeSnapshot(for: provider.id)
        historyStore?.clear(for: provider.id)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
