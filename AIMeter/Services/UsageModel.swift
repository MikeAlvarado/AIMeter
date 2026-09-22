import Foundation
import Observation
import UserNotifications
import WidgetKit
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
    private func index(for accountID: String) -> Int? {
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
    private func fetch(accountID: String) async -> Bool {
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

    #if os(macOS)
    /// The disconnected Dashboard card's way back to the zero-setup path:
    /// true once the user removed the CLI-mirrored account
    /// (`Preferences.autoDetectDeclined`), which is what stops
    /// `loadAccounts()` from re-mirroring it on every launch.
    var canRedetectClaudeCodeLogin: Bool {
        needsConnection && Preferences.autoDetectDeclined
    }

    func redetectClaudeCodeLogin() async {
        Preferences.autoDetectDeclined = false
        loadAccounts()
        await refreshAll()
    }
    #endif

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
        // The Connect sheet already refuses a taken nickname; this only
        // guarantees the registry never holds two accounts under one name.
        let name = isNameTaken(displayName) ? suggestedNickname() : displayName
        let account = ConnectedAccount(
            accountID: accountID, providerID: "claude",
            displayName: name, credentialStrategy: .managed
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
        if accounts.count == 2 {
            // The first account's queued notifications were issued with no
            // nickname prefix (a single account never needs one); now that
            // there are two, they have to say which account they're about.
            relabelPendingNotifications(except: accountID)
        }
        await refresh(accountID: accountID)
    }

    /// Replaces an existing account's credentials **in place**, keeping its
    /// `accountID` — the recovery path for a login the provider stopped
    /// accepting (`AccountUsage.needsReauthentication`). Everything keyed by
    /// that id survives untouched: stored snapshot, usage history and its
    /// pace warm-up anchor, per-account notification toggles, and the
    /// account selection of every widget already on a Home Screen. That is
    /// the whole point of not routing this through
    /// `completeConnection`, which mints a new id.
    func reconnect(accountID: String, credentials: ClaudeCredentials) async {
        guard let startIndex = index(for: accountID) else { return }
        var account = accounts[startIndex].account
        // Whatever the user just signed in with is a token pair the app
        // owns, so a macOS account that used to mirror Claude Code's login
        // stops being `.autoDetected` — and stops deferring to a CLI login
        // that just proved unusable. It also ends the refresh-token
        // standoff behind most of these failures: with its own pair,
        // AIMeter can rotate freely without invalidating the CLI's.
        let wasAutoDetected = account.credentialStrategy == .autoDetected
        if wasAutoDetected {
            account.credentialStrategy = .managed
        }
        let service = RefreshService(account: account)
        do {
            try await service.storeConnection(credentials)
        } catch {
            connectionError = (error as? UsageError)?.errorDescription ?? error.localizedDescription
            return
        }
        connectionError = nil
        // Only now that the credentials are stored. Flipping the registry
        // first and then failing the save would leave a `.managed` account
        // with nothing at its Keychain key — a permanent "no credentials"
        // card on the next launch, with the CLI login it used to mirror
        // no longer consulted either.
        if wasAutoDetected {
            registry?.setCredentialStrategy(.managed, for: accountID)
        }
        NotificationScheduler.clearReauthenticationAlert(
            accountID: accountID, preferences: preferences(for: accountID)
        )
        guard let i = index(for: accountID) else { return }
        services[accountID] = service
        accounts[i].account = account
        accounts[i].lastError = nil
        accounts[i].needsReauthentication = false
        // The macOS auto-detect candidate is only speculative until a fetch
        // confirms it (see `loadAccounts()`), so it may still be missing
        // from the registry — signing in explicitly is that confirmation.
        if registry?.account(for: accountID) == nil {
            registry?.add(account)
        }
        await refresh(accountID: accountID)
    }

    // MARK: Ordering

    /// Moves an account so it takes `targetID`'s place — what a dashboard
    /// drag-and-drop performs, once, on drop. Registry order *is* display
    /// order for every surface (dashboard, macOS menu bar popover, the
    /// all-accounts widget, and each widget's account picker), so this one
    /// write reorders them all. It also decides which account the macOS
    /// status item falls back to when no `primaryAccountID` is set:
    /// whichever ends up first.
    @discardableResult
    func moveAccount(_ accountID: String, onto targetID: String) -> Bool {
        guard accountID != targetID,
              let from = index(for: accountID),
              let to = index(for: targetID) else { return false }
        move(from: from, to: to)
        return true
    }

    /// One step up (-1) or down (+1) — the same reorder from the header's
    /// context menu, for anyone who can't drag (VoiceOver, Switch Control,
    /// or simply preferring a menu).
    func moveAccount(_ accountID: String, by offset: Int) {
        guard let from = index(for: accountID), accounts.indices.contains(from + offset) else { return }
        move(from: from, to: from + offset)
    }

    /// Deliberately hand-rolled rather than SwiftUI's
    /// `move(fromOffsets:toOffset:)`: this is a service type, and pulling
    /// SwiftUI into it just for an array shuffle isn't worth it. `to` is a
    /// destination *index* (post-removal), not an insertion offset.
    ///
    /// Both entry points are a single discrete action (a completed drop, a
    /// menu tap), so persisting and reloading widget timelines here is
    /// exactly once per reorder — which is what keeps this clear of the
    /// per-kind WidgetKit refresh budget the rest of the app depends on.
    private func move(from: Int, to: Int) {
        guard !isDemoMode, accounts.indices.contains(from), accounts.indices.contains(to) else { return }
        let moved = accounts.remove(at: from)
        accounts.insert(moved, at: min(to, accounts.count))
        registry?.replaceAll(accounts.map(\.account))
        // The all-accounts widget renders the registry in order, so it has
        // to re-render for the new one to show up there too.
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Naming

    /// Whether an account other than `excluding` already goes by `name`
    /// (trimmed, case-insensitive). The nickname is the only thing telling
    /// accounts apart in widget pickers and notification titles, so two
    /// sharing one would be indistinguishable exactly where it matters —
    /// the rename alert and the Connect sheet both gate on this, and
    /// `rename`/`completeConnection` back them up.
    func isNameTaken(_ name: String, excluding accountID: String? = nil) -> Bool {
        let candidate = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return accounts.contains {
            $0.account.accountID != accountID
                && $0.account.displayName.localizedCaseInsensitiveCompare(candidate) == .orderedSame
        }
    }

    /// Placeholder for a new account's nickname — there's no email or name
    /// signal from Claude's API to derive one from, so the user sets it or
    /// accepts this. "Claude" for the first account, then the first free
    /// "Claude N" counting from how many exist, skipping any a rename has
    /// already taken.
    func suggestedNickname() -> String {
        guard !accounts.isEmpty else { return "Claude" }
        var n = accounts.count + 1
        while isNameTaken("Claude \(n)") { n += 1 }
        return "Claude \(n)"
    }

    /// Renames an account in place — the nickname is the one thing about
    /// an account the user can change after connecting, and everything
    /// keyed by `accountID` (snapshot, history, notification toggles, Live
    /// Activity toggle, placed widgets) is untouched: a rename is never a
    /// reconnect. The name is cached in more places than the registry,
    /// though, so each is nudged here rather than left to drift until the
    /// next fetch: the per-account `RefreshService` (it feeds the Live
    /// Activity's name on every fetch), every placed widget, a Live
    /// Activity already running under the old name, and the reset/run-out
    /// notifications already queued with the old nickname in their title.
    /// An empty name (after trimming) or one another account already uses
    /// is rejected and returns `false` — the rename alert disables Save for
    /// both, but alert buttons don't re-evaluate `.disabled` live on every
    /// OS version, so the alert also reads this result to re-present itself
    /// with the reason instead of dismissing silently. An unchanged name
    /// is not a rejection.
    @discardableResult
    func rename(_ accountID: String, to newName: String) -> Bool {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isDemoMode, let i = index(for: accountID) else { return true }
        guard !name.isEmpty, !isNameTaken(name, excluding: accountID) else { return false }
        guard accounts[i].account.displayName != name else { return true }
        accounts[i].account.displayName = name
        // A no-op for macOS's still-speculative auto-detect candidate,
        // which isn't registered until a fetch confirms it —
        // `refresh(accountID:)` registers the in-memory (already renamed)
        // account at that point.
        registry?.rename(accountID, to: name)
        services[accountID] = services[accountID]?.renamed(to: name)
        propagateName(accountID: accountID)
        return true
    }

    /// Pushes an account's *current* nickname to the surfaces that cache
    /// it outside `accounts`: every placed widget (headers and the
    /// all-accounts widget read the name from the registry; one discrete
    /// reload, same as a reorder), a Live Activity already running under
    /// the old name, and the reset/run-out notifications already queued
    /// with the old nickname in their title. Called by `rename` itself and
    /// again by `refresh(accountID:)` when it finds a rename landed while
    /// its fetch was in flight — that fetch re-synced the activity and
    /// re-issued the notifications from the name it started with.
    private func propagateName(accountID: String) {
        guard let usage = usage(for: accountID) else { return }
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        LiveActivityManager.rename(
            accountID: accountID, accountName: usage.account.displayName, snapshot: usage.snapshot,
            enabled: LiveActivityPreferences(accountID: accountID).enabled
        )
        #endif
        let label = accountLabel(for: accountID)
        Task { await services[accountID]?.rescheduleNotifications(accountLabel: label) }
    }

    /// The nickname prefix on notification titles exists only once two or
    /// more accounts are connected (`accountLabel(for:)`), so crossing that
    /// line in either direction changes the copy of every *other*
    /// account's already-queued reset/run-out requests. Re-issues them
    /// from the stored snapshots, no fetch — the same nudge a rename gives
    /// one account, applied to all but `accountID`.
    private func relabelPendingNotifications(except accountID: String? = nil) {
        for entry in accounts where entry.account.accountID != accountID {
            let id = entry.account.accountID
            let label = accountLabel(for: id)
            Task { await services[id]?.rescheduleNotifications(accountLabel: label) }
        }
    }

    func disconnect(accountID: String) {
        guard let service = services[accountID] else { return }
        do {
            try service.disconnect()
            if service.account.credentialStrategy == .autoDetected {
                // See `Preferences.autoDetectDeclined`: without this the
                // CLI login comes right back on the next launch.
                Preferences.autoDetectDeclined = true
            }
            registry?.remove(accountID)
            removeAccount(accountID: accountID)
            if accounts.count == 1 {
                // Back to a single account: its queued notifications still
                // carry the nickname prefix only a multi-account install
                // needs, so re-issue them reading as they always have.
                relabelPendingNotifications()
            }
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
            // Neutral nickname on purpose — see `DemoUsageData`: the demo is
            // the source of App Store screenshots, and a provider's name in
            // a screenshot is a third-party name in store metadata (4.1(a)).
            account: ConnectedAccount(
                accountID: "demo", providerID: "claude",
                displayName: "Personal", credentialStrategy: .managed
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

    /// On by default, unlike every other toggle here — see
    /// `NotificationPreferences.reauthAlertsEnabled` for why this one family
    /// is the exception.
    func reauthAlertsEnabled(for accountID: String) -> Bool {
        _ = notificationsRevision
        return preferences(for: accountID).reauthAlertsEnabled
    }

    func setReauthAlertsEnabled(_ enabled: Bool, accountID: String) {
        let prefs = preferences(for: accountID)
        Task { @MainActor in
            guard await authorizeIfEnabling(enabled) else { return }
            prefs.reauthAlertsEnabled = enabled
            notificationsRevision += 1
            // Detection-based: fires from the next failed refresh onward.
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
