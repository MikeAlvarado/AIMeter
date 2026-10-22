import Foundation
import UsageKit

/// The providers this build knows how to talk to, by `providerID` — the
/// one place the app and the widget extension resolve a provider family
/// to a display name or to a working `UsageProvider` + credential store.
/// Adding a provider is one case in each function here plus its folder
/// under `Packages/UsageKit/.../Providers/`; nothing in the views keys on
/// a provider name (they render whatever windows a snapshot carries).
///
/// `nonisolated` for the same reason as `AppConfig`: plain constants and
/// pure functions, read from default arguments and from widget timeline
/// code that runs off the main actor.
nonisolated enum ProviderCatalog {
    /// The provider the legacy single-account install belongs to, and
    /// what an id the registry can't place fetches as.
    static let defaultProviderID = ClaudeProvider.providerID

    /// Every family this build can connect, in the order the Connect
    /// sheet's picker lists them.
    static let providerIDs = [ClaudeProvider.providerID, CodexProvider.providerID, CopilotProvider.providerID]

    /// The families Settings and Privacy & data talk about: those the
    /// connected accounts belong to, in the picker's order, so someone
    /// without Copilot reads nothing about Copilot (Mike, 2026-10-22).
    /// With nothing connected, every family, since then the text is what
    /// someone reads before choosing one.
    static func familiesToDescribe(connected providerIDs: [String]) -> [String] {
        let connected = Self.providerIDs.filter(providerIDs.contains)
        return connected.isEmpty ? Self.providerIDs : connected
    }

    /// Plain-text name shown for accounts of this family — nominative use
    /// only, never a logo (see "Design system" in the repo-root CLAUDE.md).
    static func displayName(for providerID: String) -> String {
        switch providerID {
        case ClaudeProvider.providerID: ClaudeProvider.providerDisplayName
        case CodexProvider.providerID: CodexProvider.providerDisplayName
        case CopilotProvider.providerID: CopilotProvider.providerDisplayName
        default: providerID.capitalized
        }
    }

    /// The glyph beside a family's name in the Connect sheet's picker: an
    /// SF Symbol, never a logo. Accounts themselves start on the default
    /// mark whatever their family (`ProviderMark`).
    static func symbolName(for providerID: String) -> String {
        switch providerID {
        case ClaudeProvider.providerID: "sparkle"
        case CodexProvider.providerID: "terminal"
        case CopilotProvider.providerID: "chevron.left.forwardslash.chevron.right"
        default: ProviderMark.defaultSymbol
        }
    }

    /// The pre-multi-account install's one account, and every widget's
    /// fallback when the registry is empty (nothing connected yet, or the
    /// app hasn't run its migration since this install's last update):
    /// the literal `"claude"` accountID whose Keychain item, snapshot, and
    /// history survived the upgrade unchanged.
    static var legacyAccount: ConnectedAccount {
        fallbackAccount(for: ClaudeKeychainCredentialSource.legacyAccountID)
    }

    /// What a caller holding only an accountID fetches as when the registry
    /// can't place it (a read that came back empty, or the legacy id before
    /// the migration ran): that same id — so its own Keychain key — as a
    /// managed login of the default provider. For the legacy id this is
    /// `legacyAccount` exactly; for any other it can never borrow another
    /// account's login and file that account's figures under this one.
    static func fallbackAccount(for accountID: String) -> ConnectedAccount {
        ConnectedAccount(
            accountID: accountID,
            providerID: defaultProviderID,
            displayName: displayName(for: defaultProviderID),
            credentialStrategy: .managed
        )
    }

    /// A working provider for one connected account, plus the credential
    /// store to clear on disconnect. Keyed by `account.providerID`; the
    /// credential strategy and the account's Keychain key decide which
    /// source backs it: on macOS an `.autoDetected` account mirrors the
    /// CLI's own login (Claude Code's Keychain item, Codex's auth.json),
    /// read-only; every `.managed` account has the app's own copy in the
    /// Keychain (see each provider's CLAUDE.md).
    static func makeProvider(
        for account: ConnectedAccount,
        keychain: KeychainStore,
        transport: (any HTTPTransport)? = nil
    ) -> (provider: any UsageProvider, credentials: any CredentialStore) {
        switch account.providerID {
        case ClaudeProvider.providerID:
            let key = ClaudeKeychainCredentialSource.storageKey(for: account.accountID)
            let source: any ClaudeCredentialSource
            #if os(macOS)
            if account.credentialStrategy == .autoDetected {
                source = ClaudeAutoCredentialSource(store: keychain, key: key)
            } else {
                source = ClaudeKeychainCredentialSource(store: keychain, key: key)
            }
            #else
            source = ClaudeKeychainCredentialSource(store: keychain, key: key)
            #endif
            let provider = transport.map { ClaudeProvider(credentialSource: source, transport: $0) }
                ?? ClaudeProvider(credentialSource: source)
            return (provider, source)
        case CodexProvider.providerID:
            let key = CodexKeychainCredentialSource.storageKey(for: account.accountID)
            let source: any CodexCredentialSource
            #if os(macOS)
            if account.credentialStrategy == .autoDetected {
                source = CodexFileCredentialSource()
            } else {
                source = CodexKeychainCredentialSource(store: keychain, key: key)
            }
            #else
            source = CodexKeychainCredentialSource(store: keychain, key: key)
            #endif
            let provider = transport.map { CodexProvider(credentialSource: source, transport: $0) }
                ?? CodexProvider(credentialSource: source)
            return (provider, source)
        case CopilotProvider.providerID:
            let key = CopilotKeychainCredentialSource.storageKey(for: account.accountID)
            let source = CopilotKeychainCredentialSource(store: keychain, key: key)
            let provider = transport.map { CopilotProvider(credentialSource: source, transport: $0) }
                ?? CopilotProvider(credentialSource: source)
            return (provider, source)
        default:
            // Only this app writes the registry, so an unknown family means
            // a build older than the one that wrote it. Fail loudly in
            // development; in release, treat it as the family it almost
            // certainly is rather than crash over a meter.
            assertionFailure("unknown provider \(account.providerID)")
            let claude = ConnectedAccount(
                accountID: account.accountID, providerID: ClaudeProvider.providerID,
                displayName: account.displayName, credentialStrategy: account.credentialStrategy,
                connectedAt: account.connectedAt, icon: account.icon
            )
            return makeProvider(for: claude, keychain: keychain, transport: transport)
        }
    }

    /// Where this family publishes its service health, if anywhere. Every
    /// family this build knows has a Statuspage (`StatuspageSource`); a
    /// provider without one would get nil, and the app would show nothing
    /// for it — there is nothing to show, and a guess is worse than
    /// silence.
    static func statusSource(for providerID: String, transport: (any HTTPTransport)? = nil) -> (any ServiceStatusSource)? {
        switch providerID {
        case ClaudeProvider.providerID:
            transport.map { ClaudeStatusSource(transport: $0) } ?? ClaudeStatusSource()
        case CodexProvider.providerID:
            statuspage(CodexProvider.statusSummaryEndpoint, CodexProvider.statusPageURL, transport)
        case CopilotProvider.providerID:
            statuspage(CopilotProvider.statusSummaryEndpoint, CopilotProvider.statusPageURL, transport)
        default:
            nil
        }
    }

    private static func statuspage(_ summary: URL, _ page: URL, _ transport: (any HTTPTransport)?) -> StatuspageSource {
        transport.map { StatuspageSource(summaryEndpoint: summary, pageURL: page, transport: $0) }
            ?? StatuspageSource(summaryEndpoint: summary, pageURL: page)
    }

    /// The human status page, for a banner whose incident carries no link
    /// of its own.
    static func statusPageURL(for providerID: String) -> URL? {
        switch providerID {
        case ClaudeProvider.providerID: ClaudeStatusSource.pageURL
        case CodexProvider.providerID: CodexProvider.statusPageURL
        case CopilotProvider.providerID: CopilotProvider.statusPageURL
        default: nil
        }
    }
}
