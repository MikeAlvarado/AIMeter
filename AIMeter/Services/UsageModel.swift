import Foundation
import Observation
import UserNotifications
import WidgetKit
import UsageKit
#if os(macOS)
import AppKit
#endif

/// UI-facing state for every connected account. Wraps one
/// `RefreshService` per account and keeps each account's last known
/// snapshot visible even when a refresh fails (the error is surfaced
/// alongside, per account). Split by feature across
/// `UsageModel+Connections.swift` (connect/reconnect/disconnect, demo),
/// `UsageModel+Naming.swift` (ordering and nicknames),
/// `UsageModel+Notifications.swift` (per-account toggles) and
/// `UsageModel+macOS.swift` (the refresh schedule and observers); this
/// file holds the state, loading, and the refresh path.
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
        /// The last failure was one no retry can fix (see
        /// `UsageError.requiresReauthentication`), so the surfaces showing
        /// this account swap the raw message for a "Sign in again" prompt.
        /// Signing in again is the *only* honest recovery here: the
        /// alternative a user would otherwise reach for — disconnect and
        /// add the account back — mints a fresh `accountID`, which orphans
        /// this account's history, notification preferences, Live Activity
        /// toggle, and every already-placed widget configured for it.
        var needsReauthentication = false
        var isRefreshing = false
    }

    /// `private(set)` in spirit — only this type's own files mutate it.
    var accounts: [AccountUsage] = []
    /// True while showing fabricated data from "View Demo" — lets someone
    /// (an App Store reviewer, a curious user) explore every screen without
    /// a real Claude account. Never touches `RefreshService`, the App Group
    /// `SnapshotStore`, or `WidgetCenter`, so it can never leak into
    /// widgets or a real connection.
    var isDemoMode = false
    /// Transient error from the Connect sheet's own attempt to store fresh
    /// credentials — distinct from an already-connected account's ongoing
    /// `lastError`, since a failed connection never makes it into `accounts`.
    var connectionError: String?

    /// Internal (not private) so the feature extensions in
    /// `UsageModel+*.swift` can reach them; nothing outside this type's
    /// own files should touch either.
    var services: [String: RefreshService] = [:]
    let registry: AccountRegistryStore?
    /// `peakEnabled` is the one field on `NotificationPreferences` that
    /// ignores `accountID` (peak hours is a Claude-wide policy, not tied to
    /// any one account) — "global" is a documented placeholder, never used
    /// as a real key.
    let peakPreferences = NotificationPreferences(accountID: "global")
    #if os(macOS)
    @ObservationIgnored var refreshScheduler: NSBackgroundActivityScheduler?
    #endif

    /// True when the user denied notification permission in the system
    /// settings — one OS-level toggle, not per account, so the toggles
    /// card's warning reads this shared state regardless of which
    /// account's card is showing it. Stored here (extensions can't add
    /// storage); managed in `UsageModel+Notifications.swift`.
    var notificationsBlocked = false
    /// Bumped whenever a toggle's stored value changes, so bindings that
    /// read UserDefaults through the notification getters re-evaluate.
    var notificationsRevision = 0

    /// The app's model: the App Group registry, the one-time migration,
    /// and the platform services (macOS refresh schedule and observers,
    /// the peak notification sweep).
    convenience init() {
        self.init(registry: AccountRegistryStore(suiteName: AppConfig.appGroupID), platformServices: true)
    }

    /// `platformServices: false` is the unit-test seam: no migration (it
    /// probes the real Keychain), no scheduler or observers, no
    /// notification sweep — just the registry handed in.
    init(registry: AccountRegistryStore?, platformServices: Bool) {
        self.registry = registry
        if platformServices {
            AccountMigration.run(registry: registry)
        }
        loadAccounts()
        guard platformServices else { return }
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
    func loadAccounts() {
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
        // ...unless the user explicitly disconnected that mirrored login
        // (`Preferences.autoDetectDeclined`), in which case re-mirroring it
        // here would just undo the disconnect on every launch.
        if accounts.isEmpty, !Preferences.autoDetectDeclined {
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
        let fetched = await withTaskGroup(of: Bool.self) { group in
            for account in allAccounts {
                group.addTask { @MainActor in
                    var service = RefreshService(account: account)
                    // ActivityKit refuses `Activity.request` from a
                    // background task; updates to a running one still go
                    // through.
                    service.allowsLiveActivityStart = false
                    return (try? await service.refresh(accountLabel: label(account))) != nil
                }
            }
            return await group.reduce(false) { $0 || $1 }
        }
        if fetched { WidgetCenter.shared.reloadAllTimelines() }
    }

    func refreshAll() async {
        guard !isDemoMode else { return }
        let fetched = await withTaskGroup(of: Bool.self) { group in
            for account in accounts.map(\.account) {
                group.addTask { await self.fetch(accountID: account.accountID) }
            }
            return await group.reduce(false) { $0 || $1 }
        }
        if fetched { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// This account's current array index. Never captured across an
    /// `await`: `refresh(accountID:)` runs concurrently with other accounts'
    /// refreshes on the same actor, and a concurrent disconnect or
    /// `credentialsNotFound` revert can shift or remove elements while this
    /// one is suspended — re-resolving right before each mutation is what
    /// keeps that safe instead of writing through a stale/out-of-range index.
    func index(for accountID: String) -> Int? {
        accounts.firstIndex(where: { $0.account.accountID == accountID })
    }

    func refresh(accountID: String) async {
        if await fetch(accountID: accountID) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// One account's fetch + bookkeeping. Returns whether a new snapshot
    /// reached the store — the caller's cue to reload widget timelines,
    /// which is deliberately *not* done here: the `refreshAll` sweeps fan
    /// this out per account and reload once at the end, since each
    /// `reloadAllTimelines()` draws on WidgetKit's per-kind budget and N
    /// accounts would otherwise spend it N times per sweep.
    func fetch(accountID: String) async -> Bool {
        guard !isDemoMode, let service = services[accountID],
              let startIndex = index(for: accountID), !accounts[startIndex].isRefreshing else { return false }
        accounts[startIndex].isRefreshing = true
        defer {
            if let i = index(for: accountID) { accounts[i].isRefreshing = false }
        }
        do {
            let snapshot = try await service.refresh(accountLabel: accountLabel(for: accountID))
            guard let i = index(for: accountID) else { return true }
            accounts[i].snapshot = snapshot
            accounts[i].lastError = nil
            accounts[i].needsReauthentication = false
            if registry?.account(for: accountID) == nil {
                // The in-memory account rather than `service.account`: a
                // rename during this fetch has already landed there.
                registry?.add(accounts[i].account)
            }
            if accounts[i].account.displayName != service.account.displayName {
                // A rename landed while this fetch was in flight. The
                // `service` captured above still carried the old nickname,
                // so it just synced the Live Activity and re-issued the
                // reset/run-out notifications under it — redo those nudges
                // from the current name rather than leave the old one on
                // screen until the next refresh.
                propagateName(accountID: accountID)
            }
            return true
        } catch let error as UsageError {
            if case .credentialsNotFound = error, registry?.account(for: accountID) == nil {
                // The speculative macOS auto-detect candidate turned out to
                // have nothing to detect — revert to genuinely disconnected
                // instead of leaving a permanent error card for an account
                // that was never really there.
                removeAccount(accountID: accountID)
            } else if let i = index(for: accountID) {
                accounts[i].lastError = error.errorDescription
                accounts[i].needsReauthentication = error.requiresReauthentication
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
        return false
    }

    /// Foreground-activation refresh: skips accounts whose snapshot is
    /// still fresh, so quick app switches don't refetch, but returning
    /// after a while updates the dashboard — and, via the refresh flow,
    /// pushes new snapshots to the widgets immediately.
    func refreshAllIfStale(maxAge: TimeInterval = 60) async {
        guard !isDemoMode else { return }
        let fetched = await withTaskGroup(of: Bool.self) { group in
            for entry in accounts {
                let isFresh = entry.snapshot.map { Date().timeIntervalSince($0.fetchedAt) < maxAge } ?? false
                guard !isFresh else { continue }
                group.addTask { await self.fetch(accountID: entry.account.accountID) }
            }
            return await group.reduce(false) { $0 || $1 }
        }
        if fetched { WidgetCenter.shared.reloadAllTimelines() }
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
}
