import Foundation
import WidgetKit
import UsageKit

/// Fetches usage for one connected account, persists the snapshot to the
/// App Group, reloads widget timelines, and reschedules reset
/// notifications. One instance per `ConnectedAccount` — `UsageModel` holds
/// one per registered account and fans refreshes out concurrently.
struct RefreshService {
    let account: ConnectedAccount
    let provider: ClaudeProvider
    let credentialSource: any ClaudeCredentialSource
    private let store: SnapshotStore?
    private let historyStore: UsageHistoryStore?

    init(account: ConnectedAccount) {
        self.account = account
        let credentialKey = ClaudeKeychainCredentialSource.storageKey(for: account.accountID)
        #if os(macOS)
        if account.credentialStrategy == .autoDetected {
            credentialSource = ClaudeAutoCredentialSource(store: Self.keychainStore, key: credentialKey)
        } else {
            credentialSource = ClaudeKeychainCredentialSource(store: Self.keychainStore, key: credentialKey)
        }
        #else
        credentialSource = ClaudeKeychainCredentialSource(store: Self.keychainStore, key: credentialKey)
        #endif
        provider = ClaudeProvider(credentialSource: credentialSource)
        store = SnapshotStore(suiteName: AppConfig.appGroupID)
        historyStore = UsageHistoryStore(suiteName: AppConfig.appGroupID)
    }

    static var keychainStore: KeychainStore {
        KeychainStore(service: AppConfig.keychainService, accessGroup: AppConfig.keychainAccessGroup)
    }

    /// One-time move of credentials saved before keychain sharing into the
    /// shared access group, so the widget extension can read them too. Runs
    /// once at startup (`AccountMigration`), before any account is loaded —
    /// not per-`RefreshService` instance, since it only concerns the legacy
    /// default-key item.
    static func migrateCredentialsToSharedGroup() {
        guard AppConfig.keychainAccessGroup != nil else { return }
        let legacy = KeychainStore(service: AppConfig.keychainService)
        let key = ClaudeKeychainCredentialSource.defaultKey
        guard (try? keychainStore.data(for: key)) == nil,
              let data = try? legacy.data(for: key), !data.isEmpty else { return }
        try? legacy.delete(key)
        try? keychainStore.set(data, for: key)
    }

    func lastSnapshot() -> UsageSnapshot? {
        store?.snapshot(for: account.accountID)
    }

    /// When usage history first started recording — the pace warm-up anchor.
    func paceObservingSince() -> Date? {
        historyStore?.observingSince(for: account.accountID)
    }

    /// - Parameter accountLabel: this account's nickname, to prefix onto
    ///   notification copy once more than one account is connected — nil
    ///   keeps a single-account install's copy reading exactly as it always
    ///   has. The caller already has this in memory (`UsageModel.accountLabel(for:)`
    ///   or the equivalent one-time computation in `refreshAllInBackground()`),
    ///   so `RefreshService` itself never needs to decode the account
    ///   registry just to compute it.
    @discardableResult
    func refresh(accountLabel: String?) async throws -> UsageSnapshot {
        let previous = store?.snapshot(for: account.accountID)
        let snapshot = try await provider.fetchUsage()
            .fillingMissingResets(from: previous)
        try store?.save(snapshot, for: account.accountID)
        historyStore?.record(snapshot, for: account.accountID)
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        LiveActivityManager.sync(
            accountID: account.accountID, accountName: account.displayName, snapshot: snapshot,
            enabled: LiveActivityPreferences(accountID: account.accountID).enabled
        )
        #endif

        let prefs = NotificationPreferences(accountID: account.accountID)
        await NotificationScheduler.rescheduleResets(
            for: snapshot, accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )
        await NotificationScheduler.rescheduleRunOuts(
            runOutProjections(for: snapshot), accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )
        if let previous {
            await fireDetectionAlerts(previous: previous, current: snapshot, accountLabel: accountLabel, preferences: prefs)
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
        accountLabel: String?,
        preferences prefs: NotificationPreferences
    ) async {
        await NotificationScheduler.notifyEarlyResets(
            ResetDetector.earlyResets(previous: previous, current: current),
            accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )

        let reached = ThresholdDetector.crossedUp(
            previous: previous, current: current,
            threshold: ThresholdDetector.limitReachedThreshold
        )
        await NotificationScheduler.notifyLimitReached(
            reached, in: current, accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )

        let nearing = ThresholdDetector.crossedUp(
            previous: previous, current: current,
            threshold: prefs.nearLimitThreshold
        ).filter { !reached.contains($0) }
        await NotificationScheduler.notifyNearLimit(
            nearing, in: current, accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )
    }

    /// Run-out projections for alerts: recent-rate from history when there's
    /// enough signal, otherwise the average rate (gated by a minimum used%
    /// so a barely-touched window doesn't warn). Empty before any usage.
    private func runOutProjections(for snapshot: UsageSnapshot) -> [UsageWindow.Kind: RunOutProjection] {
        var result: [UsageWindow.Kind: RunOutProjection] = [:]
        for window in snapshot.windows {
            let samples = historyStore?.samples(for: account.accountID, kind: window.kind) ?? []
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

    /// Whether this specific account's credential key already has stored
    /// credentials — used to detect a legacy single-account install during
    /// migration (`AccountMigration`).
    static func storedCredentialsExist(for accountID: String) -> Bool {
        let key = ClaudeKeychainCredentialSource.storageKey(for: accountID)
        return (try? keychainStore.data(for: key)) != nil
    }

    func storeConnection(_ credentials: ClaudeCredentials) async throws {
        try await credentialSource.save(credentials)
    }

    func disconnect() throws {
        // Cast on credentialStrategy, not platform: macOS accounts can be
        // either .autoDetected (the CLI-mirrored one) or .managed (every
        // account after the first, which always goes through the manual
        // OAuth/paste flow — same as iOS).
        if account.credentialStrategy == .autoDetected {
            #if os(macOS)
            try (credentialSource as? ClaudeAutoCredentialSource)?.clear()
            #endif
        } else {
            try (credentialSource as? ClaudeKeychainCredentialSource)?.clear()
        }
        store?.removeSnapshot(for: account.accountID)
        historyStore?.clear(for: account.accountID)
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        LiveActivityManager.end(accountID: account.accountID)
        #endif
    }
}
