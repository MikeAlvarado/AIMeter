import Foundation
import WidgetKit
import UsageKit

/// Fetches usage for one connected account, persists the snapshot to the
/// App Group, reloads widget timelines, and reschedules reset
/// notifications. One instance per `ConnectedAccount` — `UsageModel` holds
/// one per registered account and fans refreshes out concurrently.
struct RefreshService {
    /// `private(set) var` rather than `let` for exactly one mutation,
    /// `renamed(to:)`: `displayName` is the only field of an account that
    /// can change without invalidating the credential source built in
    /// `init`, which depends on `accountID` and `credentialStrategy`
    /// alone. A strategy change still rebuilds the whole service
    /// (`UsageModel.reconnect`).
    private(set) var account: ConnectedAccount
    /// Built by `ProviderCatalog.makeProvider` from `account.providerID` —
    /// nothing in this type knows which provider it's refreshing.
    let provider: any UsageProvider
    let credentialSource: any CredentialStore
    /// Whether a fetch may *start* a Live Activity (iOS). ActivityKit only
    /// honours `Activity.request` from the foreground app, so the
    /// `BGAppRefreshTask` path (`UsageModel.refreshAllInBackground`) turns
    /// this off — updating one already running is fine from anywhere in
    /// the app process.
    var allowsLiveActivityStart = true
    private let store: SnapshotStore?
    private let historyStore: UsageHistoryStore?

    init(account: ConnectedAccount) {
        self.account = account
        (provider, credentialSource) = ProviderCatalog.makeProvider(for: account, keychain: Self.keychainStore)
        store = SnapshotStore(suiteName: AppConfig.appGroupID)
        historyStore = UsageHistoryStore(suiteName: AppConfig.appGroupID)
    }

    static var keychainStore: KeychainStore {
        KeychainStore(service: AppConfig.keychainService, accessGroup: AppConfig.keychainAccessGroup)
    }

    /// The same service under a new nickname. Keeps the provider — and with
    /// it any in-memory cache it holds (the CLI-mirrored macOS account's
    /// plan cache, see `ClaudeProvider`'s `PlanCache`) — where rebuilding the
    /// service the way a reconnect must would throw that away for a change
    /// that touches no credential.
    func renamed(to displayName: String) -> RefreshService {
        var copy = self
        copy.account.displayName = displayName
        return copy
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
        let prefs = NotificationPreferences(accountID: account.accountID)

        let snapshot: UsageSnapshot
        do {
            snapshot = try await provider.fetchUsage()
                .fillingMissingResets(from: previous)
        } catch {
            // Only `notAuthenticated` alerts, not everything
            // `requiresReauthentication` covers: `tokenExpired` on macOS
            // just means Claude Code hasn't rotated its own token yet (the
            // CLI heals that on its next run), and `credentialsNotFound` is
            // also what the speculative macOS auto-detect candidate throws
            // when there's no CLI login to mirror — an account the app then
            // drops rather than keeps. Notifying about either would be
            // crying wolf; both still show the in-app sign-in affordance,
            // which costs nothing when it turns out to be unnecessary.
            if case UsageError.notAuthenticated = error {
                await NotificationScheduler.notifyReauthenticationNeeded(
                    accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
                )
            }
            throw error
        }
        // Fetching at all proves the credentials work, so re-arm the alert
        // for a future breakage (no-op unless one was actually delivered).
        NotificationScheduler.clearReauthenticationAlert(accountID: account.accountID, preferences: prefs)

        try store?.save(snapshot, for: account.accountID)
        historyStore?.record(snapshot, for: account.accountID)
        // No `reloadAllTimelines()` here: the caller reloads once per sweep
        // (see `UsageModel.fetch(accountID:)`), not once per account.
        #if os(iOS)
        LiveActivityManager.sync(
            accountID: account.accountID, accountName: account.displayName,
            providerID: account.providerID, snapshot: snapshot,
            enabled: LiveActivityPreferences(accountID: account.accountID).enabled,
            mayStart: allowsLiveActivityStart
        )
        #endif

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

    /// Re-issues this account's two *scheduled* notification families
    /// (`reset.`, `runout.`) from the stored snapshot, without fetching.
    /// `refresh` already does this after every successful fetch; this is
    /// for the one change that alters pending notification copy with no
    /// fetch involved — a rename, whose new nickname would otherwise wait
    /// for the next refresh to reach titles already queued under the old
    /// one. The detection-based families fire immediately, so they have
    /// nothing pending to rename.
    func rescheduleNotifications(accountLabel: String?) async {
        guard let snapshot = lastSnapshot() else { return }
        let prefs = NotificationPreferences(accountID: account.accountID)
        await NotificationScheduler.rescheduleResets(
            for: snapshot, accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )
        await NotificationScheduler.rescheduleRunOuts(
            runOutProjections(for: snapshot), accountID: account.accountID, accountLabel: accountLabel, preferences: prefs
        )
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

    /// The Claude connect path: the one place this type is provider-typed,
    /// because the credentials themselves are (`ClaudeCredentials` from the
    /// in-app OAuth exchange or a pasted JSON). A second provider adds its
    /// own connect path beside this one rather than generalizing it.
    func storeConnection(_ credentials: ClaudeCredentials) async throws {
        guard let source = credentialSource as? any ClaudeCredentialSource else {
            throw UsageError.storage("account \(account.accountID) is not a \(ClaudeProvider.providerDisplayName) account")
        }
        try await source.save(credentials)
    }

    func disconnect() throws {
        // Whatever backs this account — the CLI mirror's fallback copy, or
        // the app's own Keychain item — `CredentialStore.clear` removes it
        // without this type knowing which.
        try credentialSource.clear()
        store?.removeSnapshot(for: account.accountID)
        historyStore?.clear(for: account.accountID)
        WidgetCenter.shared.reloadAllTimelines()
        // Everything else keyed by this accountID goes too: the reset/
        // run-out requests still queued for it (they'd fire at their
        // `resetsAt` for an account that no longer exists), whatever it
        // delivered, and its per-account toggles — otherwise a UUID's
        // worth of keys leaks into the App Group forever.
        let accountID = account.accountID
        Task { await NotificationScheduler.removeAll(accountID: accountID) }
        NotificationPreferences(accountID: accountID).clear()
        #if os(iOS)
        LiveActivityManager.end(accountID: accountID)
        LiveActivityPreferences(accountID: accountID).clear()
        #endif
    }
}
