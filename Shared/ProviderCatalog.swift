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
    /// The provider a new connection belongs to. There is exactly one
    /// today; the Connect sheet gets a picker the day there are two.
    static let defaultProviderID = ClaudeProvider.providerID

    /// Plain-text name shown for accounts of this family — nominative use
    /// only, never a logo (see "Design system" in the repo-root CLAUDE.md).
    static func displayName(for providerID: String) -> String {
        switch providerID {
        case ClaudeProvider.providerID: ClaudeProvider.providerDisplayName
        default: providerID.capitalized
        }
    }

    /// The pre-multi-account install's one account, and every widget's
    /// fallback when the registry is empty (nothing connected yet, or the
    /// app hasn't run its migration since this install's last update):
    /// the literal `"claude"` accountID whose Keychain item, snapshot, and
    /// history survived the upgrade unchanged.
    static var legacyAccount: ConnectedAccount {
        ConnectedAccount(
            accountID: ClaudeKeychainCredentialSource.legacyAccountID,
            providerID: ClaudeProvider.providerID,
            displayName: displayName(for: ClaudeProvider.providerID),
            credentialStrategy: .managed
        )
    }

    /// A working provider for one connected account, plus the credential
    /// store to clear on disconnect. Keyed by `account.providerID`; the
    /// credential strategy and the account's Keychain key decide which
    /// source backs it (see the Claude provider's CLAUDE.md for the
    /// `.autoDetected` / `.managed` split).
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
        default:
            // Only this app writes the registry, so an unknown family means
            // a build older than the one that wrote it. Fail loudly in
            // development; in release, treat it as the family it almost
            // certainly is rather than crash over a meter.
            assertionFailure("unknown provider \(account.providerID)")
            var claude = account
            claude = ConnectedAccount(
                accountID: claude.accountID, providerID: ClaudeProvider.providerID,
                displayName: claude.displayName, credentialStrategy: claude.credentialStrategy,
                connectedAt: claude.connectedAt
            )
            return makeProvider(for: claude, keychain: keychain, transport: transport)
        }
    }
}
