import Foundation
import WidgetKit
import UsageKit

/// Adding, repairing, and removing accounts, plus demo mode — the parts
/// of `UsageModel` that change *which* accounts exist. See the type doc
/// in `UsageModel.swift` for how the files divide.
extension UsageModel {
    // MARK: - Account management

    /// Called by the Connect sheet after a successful sign-in of any
    /// family (`ProviderLogin`). Adds a new account with the app's own
    /// managed credentials — never the macOS auto-detect path, which only
    /// ever applies to a CLI login found on this Mac, not a sign-in.
    func completeConnection(_ login: ProviderLogin, displayName: String? = nil) async {
        let accountID = UUID().uuidString
        // The Connect sheet already refuses a taken nickname; this only
        // guarantees the registry never holds two accounts under one name.
        let requested = displayName ?? suggestedNickname(providerID: login.providerID)
        let name = isNameTaken(requested) ? suggestedNickname(providerID: login.providerID) : requested
        let account = ConnectedAccount(
            accountID: accountID, providerID: login.providerID,
            displayName: name, credentialStrategy: .managed
        )
        let service = RefreshService(account: account)
        do {
            try await service.storeConnection(login)
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
    func reconnect(accountID: String, login: ProviderLogin) async {
        guard let startIndex = index(for: accountID) else { return }
        var account = accounts[startIndex].account
        guard account.providerID == login.providerID else {
            connectionError = String(localized: "That sign-in is for another service than this account.")
            return
        }
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
            try await service.storeConnection(login)
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

    func disconnect(accountID: String) {
        guard let service = services[accountID] else { return }
        do {
            try service.disconnect()
            if service.account.credentialStrategy == .autoDetected, service.account.providerID == ClaudeProvider.providerID {
                // See `Preferences.autoDetectDeclined`: without this the
                // CLI login comes right back on the next launch. Only
                // Claude's is ever mirrored speculatively; Codex's is
                // connected on purpose and stays gone when removed.
                Preferences.autoDetectDeclined = true
            }
            if let identity = service.account.syncIdentity ?? registry?.account(for: accountID)?.syncIdentity {
                cloud?.removeHistory(identity: identity)
            }
            registry?.remove(accountID)
            removeAccount(accountID: accountID)
            notifyWatch()
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
    func addAccount(_ account: ConnectedAccount, service: RefreshService, snapshot: UsageSnapshot? = nil) {
        services[account.accountID] = service
        accounts.append(AccountUsage(account: account, snapshot: snapshot))
    }

    func removeAccount(accountID: String) {
        services.removeValue(forKey: accountID)
        accounts.removeAll { $0.account.accountID == accountID }
    }

    // MARK: - Demo mode

    func enterDemoMode() {
        isDemoMode = true
        connectionError = nil
        // Two fabricated accounts (see `DemoUsageData.accounts`), so the
        // demo — the source of App Store screenshots — shows the
        // multi-account dashboard and a per-account icon.
        accounts = DemoUsageData.accounts().map { AccountUsage(account: $0.account, snapshot: $0.snapshot) }
        #if os(macOS)
        claudeCode?.enterDemo()
        DemoSessions.shared.reset()
        #endif
        applyAccountOrder()
        notifyWatch()
    }

    func exitDemoMode() {
        guard isDemoMode else { return }
        isDemoMode = false
        connectionError = nil
        #if os(macOS)
        claudeCode?.exitDemo()
        #else
        endDemoLiveActivities()
        #endif
        loadAccounts()
    }

    #if os(iOS)
    /// A Live Activity turned on in the demo counts down fabricated
    /// figures, so it ends with the demo and its switches go with it; one
    /// a demo left running when the app was quit ends at the next launch.
    func endDemoLiveActivities() {
        for (account, _) in DemoUsageData.accounts() {
            LiveActivityManager.end(accountID: account.accountID)
            LiveActivityPreferences(accountID: account.accountID).clear()
        }
    }
    #endif

    #if os(macOS)
    /// Whether the Connect sheet may offer the login the Codex CLI keeps
    /// on this Mac: the file holds one, and no account mirrors it yet
    /// (the CLI tracks one login per machine, so one account is the cap,
    /// as for Claude Code's).
    var canConnectCodexCLILogin: Bool {
        CodexFileCredentialSource.isAvailable
            && !accounts.contains { $0.account.providerID == CodexProvider.providerID && $0.account.credentialStrategy == .autoDetected }
    }

    /// Connects the login the Codex CLI keeps on this Mac as a read-only
    /// mirror (`.autoDetected`, `CodexFileCredentialSource`), the Codex
    /// counterpart of the Claude Code login the first account mirrors;
    /// unlike that one it is never guessed at launch, only added here.
    /// Signing in again later makes it `.managed` (`reconnect`).
    func connectCodexCLILogin(displayName: String? = nil) async {
        guard canConnectCodexCLILogin else { return }
        let requested = displayName ?? suggestedNickname(providerID: CodexProvider.providerID)
        let name = isNameTaken(requested) ? suggestedNickname(providerID: CodexProvider.providerID) : requested
        let account = ConnectedAccount(
            accountID: UUID().uuidString, providerID: CodexProvider.providerID,
            displayName: name, credentialStrategy: .autoDetected
        )
        connectionError = nil
        registry?.add(account)
        addAccount(account, service: RefreshService(account: account))
        if accounts.count == 2 {
            relabelPendingNotifications(except: account.accountID)
        }
        await refresh(accountID: account.accountID)
    }

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
}
