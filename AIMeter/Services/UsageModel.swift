import Foundation
import Observation
import UserNotifications
import UsageKit
#if os(macOS)
import AppKit
#endif

/// UI-facing state for every connected Claude account. Wraps one
/// `RefreshService` per account and keeps each account's last known
/// snapshot visible even when a refresh fails (the error is surfaced
/// alongside, per account).
///
/// `isRefreshing` and `needsConnection` below are true aggregates over every
/// connected account (not a first-account shim), read by surfaces that only
/// need a glance-level "is anything busy / is anything connected at all".
/// `@MainActor`: `refreshAll()` fans out concurrent fetches via a
/// `TaskGroup`, and each one mutates a different element of the shared
/// `accounts` array on completion. Isolating the whole class serializes
/// those mutations (safe) while each `refresh(accountID:)` call's own
/// `await service.refresh()` network request still suspends off the main
/// actor, so the fetches themselves still run concurrently — only the
/// bookkeeping before/after each one is serialized.
@MainActor
@Observable
final class UsageModel {
    struct AccountUsage: Identifiable {
        var id: String { account.accountID }
        var account: ConnectedAccount
        var snapshot: UsageSnapshot?
        var lastError: String?
        var isRefreshing = false
    }

    private(set) var accounts: [AccountUsage] = []
    /// True while showing fabricated data from "View Demo" — lets someone
    /// (an App Store reviewer, a curious user) explore every screen without
    /// a real Claude account. Never touches `RefreshService`, the App Group
    /// `SnapshotStore`, or `WidgetCenter`, so it can never leak into
    /// widgets or a real connection.
    private(set) var isDemoMode = false
    /// Transient error from the Connect sheet's own attempt to store fresh
    /// credentials — distinct from an already-connected account's ongoing
    /// `lastError`, since a failed connection never makes it into `accounts`.
    private(set) var connectionError: String?

    private var services: [String: RefreshService] = [:]
    private let registry: AccountRegistryStore?
    /// `peakEnabled` is the one field on `NotificationPreferences` that
    /// ignores `accountID` (peak hours is a Claude-wide policy, not tied to
    /// any one account) — "global" is a documented placeholder, never used
    /// as a real key.
    private let peakPreferences = NotificationPreferences(accountID: "global")
    #if os(macOS)
    @ObservationIgnored private var refreshScheduler: NSBackgroundActivityScheduler?
    #endif

    init() {
        registry = AccountRegistryStore(suiteName: AppConfig.appGroupID)
        AccountMigration.run(registry: registry)
        loadAccounts()
        #if os(macOS)
        AppEnvironment.shared = self
        rebuildRefreshSchedule(interval: Preferences.load().refreshCadence.interval)
        observeWake()
        observeActivation()
        #endif
        // Peak-hours alerts come from a fixed weekday schedule, not a
        // fetched snapshot, so they only need scheduling once here (and
        // whenever the toggle changes) — not on every refresh.
        Task { await NotificationScheduler.reschedulePeakNotifications(preferences: peakPreferences) }
    }

    /// Reuses any already-live `RefreshService` per account (keyed off the
    /// previous `services` dict) instead of rebuilding one from scratch —
    /// `loadAccounts()` runs more than once per process (`init`, and
    /// `exitDemoMode()`), and on macOS a fresh `ClaudeAutoCredentialSource`
    /// would drop its cached read of Claude Code's Keychain item, which
    /// exists specifically to avoid re-prompting for Keychain access on
    /// every refresh — see `ClaudeAutoCredentialSource.cachedLocal`.
    private func loadAccounts() {
        let previousServices = services
        let connected = registry?.accounts() ?? []
        services = Dictionary(uniqueKeysWithValues: connected.map { account in
            (account.accountID, previousServices[account.accountID] ?? RefreshService(account: account))
        })
        accounts = connected.map { AccountUsage(account: $0, snapshot: services[$0.accountID]?.lastSnapshot()) }
        #if os(macOS)
        // Nothing registered yet: speculatively try the CLI-mirrored login
        // rather than assuming disconnected — this mirrors the pre-multi-
        // account behavior of optimistically showing content until the
        // first refresh proves there's nothing to show. Not persisted to
        // the registry until that refresh actually confirms real
        // credentials (see `refresh(accountID:)`), so a Mac with no Claude
        // Code login never gets a phantom account.
        if accounts.isEmpty {
            let candidate = ConnectedAccount(
                accountID: ClaudeKeychainCredentialSource.legacyAccountID, providerID: "claude",
                displayName: "Claude", credentialStrategy: .autoDetected
            )
            let service = previousServices[candidate.accountID] ?? RefreshService(account: candidate)
            services[candidate.accountID] = service
            accounts = [AccountUsage(account: candidate, snapshot: service.lastSnapshot())]
        }
        #endif
    }

    // MARK: - Refresh

    /// Standalone refresh path for the iOS `BGAppRefreshTask`, which runs
    /// in a context with no live `UsageModel` instance to reuse.
    static func refreshAllInBackground() async {
        guard let registry = AccountRegistryStore(suiteName: AppConfig.appGroupID) else { return }
        let allAccounts = registry.accounts()
        let label: (ConnectedAccount) -> String? = { allAccounts.count > 1 ? $0.displayName : nil }
        await withTaskGroup(of: Void.self) { group in
            for account in allAccounts {
                group.addTask { _ = try? await RefreshService(account: account).refresh(accountLabel: label(account)) }
            }
        }
    }

    func refreshAll() async {
        guard !isDemoMode else { return }
        await withTaskGroup(of: Void.self) { group in
            for account in accounts.map(\.account) {
                group.addTask { await self.refresh(accountID: account.accountID) }
            }
        }
    }

    /// This account's current array index. Never captured across an
    /// `await`: `refresh(accountID:)` runs concurrently with other accounts'
    /// refreshes on the same actor, and a concurrent disconnect or
    /// `credentialsNotFound` revert can shift or remove elements while this
    /// one is suspended — re-resolving right before each mutation is what
    /// keeps that safe instead of writing through a stale/out-of-range index.
    private func index(for accountID: String) -> Int? {
        accounts.firstIndex(where: { $0.account.accountID == accountID })
    }

    func refresh(accountID: String) async {
        guard !isDemoMode, let service = services[accountID],
              let startIndex = index(for: accountID), !accounts[startIndex].isRefreshing else { return }
        accounts[startIndex].isRefreshing = true
        defer {
            if let i = index(for: accountID) { accounts[i].isRefreshing = false }
        }
        do {
            let snapshot = try await service.refresh(accountLabel: accountLabel(for: accountID))
            guard let i = index(for: accountID) else { return }
            accounts[i].snapshot = snapshot
            accounts[i].lastError = nil
            if registry?.account(for: accountID) == nil {
                registry?.add(service.account)
            }
        } catch let error as UsageError {
            if case .credentialsNotFound = error, registry?.account(for: accountID) == nil {
                // The speculative macOS auto-detect candidate turned out to
                // have nothing to detect — revert to genuinely disconnected
                // instead of leaving a permanent error card for an account
                // that was never really there.
                removeAccount(accountID: accountID)
            } else if let i = index(for: accountID) {
                accounts[i].lastError = error.errorDescription
            }
        } catch is CancellationError {
            // A superseded refresh (pull-to-refresh released, scene change)
            // is not an error worth showing.
        } catch let error as URLError where error.code == .cancelled {
            // Same: the URL task was cancelled by a newer refresh.
        } catch {
            if let i = index(for: accountID) {
                accounts[i].lastError = error.localizedDescription
            }
        }
    }

    /// Foreground-activation refresh: skips accounts whose snapshot is
    /// still fresh, so quick app switches don't refetch, but returning
    /// after a while updates the dashboard — and, via the refresh flow,
    /// pushes new snapshots to the widgets immediately.
    func refreshAllIfStale(maxAge: TimeInterval = 60) async {
        guard !isDemoMode else { return }
        await withTaskGroup(of: Void.self) { group in
            for entry in accounts {
                let isFresh = entry.snapshot.map { Date().timeIntervalSince($0.fetchedAt) < maxAge } ?? false
                guard !isFresh else { continue }
                group.addTask { await self.refresh(accountID: entry.account.accountID) }
            }
        }
    }

    var isRefreshing: Bool { accounts.contains { $0.isRefreshing } }
    /// True when there are no usable accounts — dashboard shows the connect
    /// card instead of usage rows.
    var needsConnection: Bool { accounts.isEmpty }

    /// This account's current `AccountUsage`, if still connected.
    func usage(for accountID: String) -> AccountUsage? {
        accounts.first { $0.account.accountID == accountID }
    }

    /// True once pace has warmed up (a couple of sessions observed since
    /// this account connected). Until then, views withhold the pace caption
    /// and the forecast, showing a "learning" state instead of asserting a
    /// pace from too little history.
    func paceReady(for accountID: String) -> Bool {
        // Demo data has no real observation history to warm up from — treat
        // it as always ready so the pace captions and Forecast card show
        // their full state instead of "Learning your pace…".
        if isDemoMode { return true }
        return PaceCalculator.isReady(observingSince: services[accountID]?.paceObservingSince())
    }

    /// Resolves the macOS menu bar's single status item to one account:
    /// the user's chosen primary when it's still connected, else the first
    /// connected account. `MenuBarExtra` has no per-instance configuration
    /// the way widgets do, so this "primary" concept only exists here.
    func primaryAccountUsage(preferredID: String?) -> AccountUsage? {
        if let preferredID, let match = usage(for: preferredID) {
            return match
        }
        return accounts.first
    }

    // MARK: - Account management

    /// Called by the connect sheet after a successful OAuth exchange. Adds
    /// a new account (the app's own managed credentials — never the
    /// macOS auto-detect path, which only ever applies to a CLI-mirrored
    /// login found automatically, not a manual paste/OAuth flow).
    func completeConnection(_ credentials: ClaudeCredentials, displayName: String = "Claude") async {
        let accountID = UUID().uuidString
        let account = ConnectedAccount(
            accountID: accountID, providerID: "claude",
            displayName: displayName, credentialStrategy: .managed
        )
        let service = RefreshService(account: account)
        do {
            try await service.storeConnection(credentials)
        } catch {
            connectionError = (error as? UsageError)?.errorDescription ?? error.localizedDescription
            return
        }
        connectionError = nil
        registry?.add(account)
        addAccount(account, service: service)
        await refresh(accountID: accountID)
    }

    func disconnect(accountID: String) {
        guard let service = services[accountID] else { return }
        do {
            try service.disconnect()
            registry?.remove(accountID)
            removeAccount(accountID: accountID)
        } catch {
            if let index = index(for: accountID) {
                accounts[index].lastError = error.localizedDescription
            }
        }
    }

    /// `accounts` and `services` must always move in lockstep — a service
    /// with no matching `accounts` row (or vice versa) makes that account
    /// silently unrefreshable. These are the only two places either
    /// collection grows or shrinks by one account (`loadAccounts()` is
    /// exempt: it rebuilds both wholesale in a single pass).
    private func addAccount(_ account: ConnectedAccount, service: RefreshService, snapshot: UsageSnapshot? = nil) {
        services[account.accountID] = service
        accounts.append(AccountUsage(account: account, snapshot: snapshot))
    }

    private func removeAccount(accountID: String) {
        services.removeValue(forKey: accountID)
        accounts.removeAll { $0.account.accountID == accountID }
    }

    // MARK: - Demo mode

    func enterDemoMode() {
        isDemoMode = true
        connectionError = nil
        accounts = [AccountUsage(
            account: ConnectedAccount(
                accountID: "demo", providerID: "claude",
                displayName: "Claude", credentialStrategy: .managed
            ),
            snapshot: DemoUsageData.snapshot()
        )]
    }

    func exitDemoMode() {
        guard isDemoMode else { return }
        isDemoMode = false
        connectionError = nil
        loadAccounts()
    }

    // MARK: - Notification preferences (per account, except peak — see above)

    /// True when the user denied notification permission in the system
    /// settings — one OS-level toggle, not per account, so the toggles
    /// card's warning reads this shared state regardless of which
    /// account's card is showing it.
    private(set) var notificationsBlocked = false
    /// Bumped whenever a toggle's stored value changes, so bindings that
    /// read UserDefaults through `notificationsEnabled` re-evaluate.
    private var notificationsRevision = 0

    func refreshNotificationAuthorization() async {
        let status = await NotificationScheduler.authorizationStatus()
        await MainActor.run { notificationsBlocked = status == .denied }
    }

    private func preferences(for accountID: String) -> NotificationPreferences {
        NotificationPreferences(accountID: accountID)
    }

    /// Label passed to `NotificationScheduler` so a two-or-more-account
    /// install's notifications name the account they're about; a single
    /// account's copy stays exactly as it always read.
    private func accountLabel(for accountID: String) -> String? {
        guard accounts.count > 1 else { return nil }
        return usage(for: accountID)?.account.displayName
    }

    func notificationsEnabled(for kind: UsageWindow.Kind, accountID: String) -> Bool {
        _ = notificationsRevision
        return preferences(for: accountID).isEnabled(for: kind)
    }

    func setNotificationsEnabled(_ enabled: Bool, for kind: UsageWindow.Kind, accountID: String) {
        // Never schedule a real notification off fabricated demo resets.
        let snapshot = isDemoMode ? nil : usage(for: accountID)?.snapshot
        let prefs = preferences(for: accountID)
        let label = accountLabel(for: accountID)
        Task { @MainActor in
            if enabled {
                guard await NotificationScheduler.ensureAuthorization() else {
                    // Denied: don't persist the toggle — snap it back off
                    // and surface the blocked state.
                    notificationsBlocked = true
                    notificationsRevision += 1
                    return
                }
                notificationsBlocked = false
            }
            prefs.setEnabled(enabled, for: kind)
            notificationsRevision += 1
            await NotificationScheduler.rescheduleResets(
                for: snapshot, accountID: accountID, accountLabel: label, preferences: prefs
            )
        }
    }

    // MARK: Smart notifications (per account: run-out / early-reset / near-limit / limit-reached)

    func runOutWarningsEnabled(for accountID: String) -> Bool {
        _ = notificationsRevision
        return preferences(for: accountID).runOutWarningsEnabled
    }

    func earlyResetAlertsEnabled(for accountID: String) -> Bool {
        _ = notificationsRevision
        return preferences(for: accountID).earlyResetAlertsEnabled
    }

    func setRunOutWarningsEnabled(_ enabled: Bool, accountID: String) {
        // Never schedule a real notification off fabricated demo resets.
        let snapshot = isDemoMode ? nil : usage(for: accountID)?.snapshot
        let prefs = preferences(for: accountID)
        let label = accountLabel(for: accountID)
        Task { @MainActor in
            guard await authorizeIfEnabling(enabled) else { return }
            prefs.runOutWarningsEnabled = enabled
            notificationsRevision += 1
            // Immediate scheduling uses the average rate (no history needed);
            // the next fetch refines it with the recent rate.
            let projections = snapshot.map {
                RunOutPredictor.averageProjections(for: $0, minimumUsedPct: RunOutPredictor.alertMinimumUsedPct)
            } ?? [:]
            await NotificationScheduler.rescheduleRunOuts(
                projections, accountID: accountID, accountLabel: label, preferences: prefs
            )
        }
    }

    func setEarlyResetAlertsEnabled(_ enabled: Bool, accountID: String) {
        let prefs = preferences(for: accountID)
        Task { @MainActor in
            guard await authorizeIfEnabling(enabled) else { return }
            prefs.earlyResetAlertsEnabled = enabled
            notificationsRevision += 1
            // Nothing to schedule now — these fire on detection at fetch time.
        }
    }

    func nearLimitEnabled(for accountID: String) -> Bool {
        _ = notificationsRevision
        return preferences(for: accountID).nearLimitEnabled
    }

    func nearLimitThreshold(for accountID: String) -> Double {
        _ = notificationsRevision
        return preferences(for: accountID).nearLimitThreshold
    }

    func limitReachedEnabled(for accountID: String) -> Bool {
        _ = notificationsRevision
        return preferences(for: accountID).limitReachedEnabled
    }

    func setNearLimitEnabled(_ enabled: Bool, accountID: String) {
        let prefs = preferences(for: accountID)
        Task { @MainActor in
            guard await authorizeIfEnabling(enabled) else { return }
            prefs.nearLimitEnabled = enabled
            notificationsRevision += 1
            // Detection-based: fires on the next crossing at fetch time.
        }
    }

    func setNearLimitThreshold(_ threshold: Double, accountID: String) {
        preferences(for: accountID).nearLimitThreshold = threshold
        notificationsRevision += 1
    }

    func setLimitReachedEnabled(_ enabled: Bool, accountID: String) {
        let prefs = preferences(for: accountID)
        Task { @MainActor in
            guard await authorizeIfEnabling(enabled) else { return }
            prefs.limitReachedEnabled = enabled
            notificationsRevision += 1
        }
    }

    // MARK: Peak-hours alerts (global — see `peakPreferences` above)

    var peakNotificationsEnabled: Bool {
        _ = notificationsRevision
        return peakPreferences.peakEnabled
    }

    func setPeakNotificationsEnabled(_ enabled: Bool) {
        Task { @MainActor in
            guard await authorizeIfEnabling(enabled) else { return }
            peakPreferences.peakEnabled = enabled
            notificationsRevision += 1
            await NotificationScheduler.reschedulePeakNotifications(preferences: peakPreferences)
        }
    }

    /// Shared permission gate for enabling a notification toggle: a denied
    /// system permission snaps the toggle back off and surfaces the blocked
    /// state. Returns whether the caller should proceed to persist.
    private func authorizeIfEnabling(_ enabled: Bool) async -> Bool {
        if enabled {
            guard await NotificationScheduler.ensureAuthorization() else {
                notificationsBlocked = true
                notificationsRevision += 1
                return false
            }
            notificationsBlocked = false
        }
        return true
    }

    // MARK: - macOS refresh schedule

    #if os(macOS)
    /// Rebuilds the repeating refresh at the user's cadence.
    ///
    /// `NSBackgroundActivityScheduler` rather than a run-loop `Timer`: a
    /// menu-bar-only app with no visible window is a prime App Nap
    /// candidate — which is exactly what AIMeter becomes once the Dock icon
    /// is hidden — and Nap throttles timers unpredictably. The scheduler is
    /// Nap- and power-aware, and trades an exact fire instant (nothing here
    /// needs one) for actually running.
    func rebuildRefreshSchedule(interval: TimeInterval) {
        refreshScheduler?.invalidate()
        let scheduler = NSBackgroundActivityScheduler(identifier: AppConfig.refreshActivityID)
        scheduler.repeats = true
        scheduler.interval = interval
        // The cadence is a "roughly every N" contract, not a deadline, so a
        // wide tolerance lets the system coalesce this with other wake-ups
        // instead of waking the CPU on AIMeter's account alone.
        scheduler.tolerance = interval * 0.2
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            // Called off the main actor; hop back before touching the model,
            // and report completion so the scheduler re-arms.
            Task { @MainActor in
                await AppEnvironment.shared?.refreshAll()
                completion(.finished)
            }
        }
        refreshScheduler = scheduler
        Preferences.recordScheduled()
    }

    /// Neither a scheduler nor a timer fires while the Mac is asleep. Waking
    /// does re-arm the schedule, but not necessarily right away, so nudge it
    /// — `refreshAllIfStale` decides whether anything is actually due,
    /// making this a no-op when every snapshot is still fresh.
    ///
    /// Registered once, from `init`: the model is owned by the App scene for
    /// the whole process lifetime, and the closure holds nothing strongly
    /// (it reaches the model through the same weak `AppEnvironment` the
    /// schedule uses), so there is no observer to unregister before exit.
    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let cadence = Preferences.load().refreshCadence.interval
                await AppEnvironment.shared?.refreshAllIfStale(maxAge: cadence)
            }
        }
    }

    /// The iOS side already re-checks notification authorization whenever
    /// `scenePhase` returns to `.active` ("the user may have flipped the
    /// permission in Settings" — `ContentView`), because System Settings and
    /// the app trade the foreground there. macOS has no scene phase, but the
    /// same trip — alt-tab to System Settings, flip the toggle, alt-tab back
    /// — is if anything more common on a desktop, and `notificationsBlocked`
    /// (the in-app warning banner, and the stale value a toggle's `.denied`
    /// check can otherwise race right after such a change) was only ever
    /// getting refreshed when a Provider Detail view happened to re-appear.
    /// `didBecomeActiveNotification` is the direct macOS equivalent of that
    /// iOS signal. Same no-unregister reasoning as `observeWake()`.
    private func observeActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await AppEnvironment.shared?.refreshNotificationAuthorization()
            }
        }
    }
    #endif
}

#if os(macOS)
/// Lets the background refresh schedule and the wake observer reach the
/// live model from closures that can't capture it strongly.
enum AppEnvironment {
    static weak var shared: UsageModel?
}
#endif
