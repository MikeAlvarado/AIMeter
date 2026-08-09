import Foundation
#if os(macOS)

/// macOS credential strategy: prefer the login Claude Code already
/// maintains locally (zero setup, read-only); fall back to the app's own
/// Keychain copy obtained through the in-app OAuth flow.
///
/// Refresh is only allowed when the credentials came from the app's own
/// copy — rotating Claude Code's refresh token would log the CLI out.
public final class ClaudeAutoCredentialSource: ClaudeCredentialSource, @unchecked Sendable {
    private let local = ClaudeCodeLocalCredentialSource()
    private let fallback: ClaudeKeychainCredentialSource
    private let lock = NSLock()
    private var lastLoadWasLocal = true
    /// The last credentials read from Claude Code's Keychain item, reused
    /// while still valid so a re-fetch doesn't re-read the item on every
    /// refresh cycle. Reading a foreign app's Keychain item requires macOS
    /// authorization each time its access grant has lapsed — which happens
    /// whenever Claude Code itself rewrites that item (e.g. its own token
    /// rotation resets the item's trusted-app list) — so this is what keeps
    /// the "AIMeter wants to access…" prompt from firing on every refresh
    /// instead of roughly once per access-token lifetime.
    private var cachedLocal: ClaudeCredentials?

    public var allowsRefresh: Bool {
        lock.withLock { !lastLoadWasLocal }
    }

    public init(store: KeychainStore, key: String = ClaudeKeychainCredentialSource.defaultKey) {
        fallback = ClaudeKeychainCredentialSource(store: store, key: key)
    }

    public func load() async throws -> ClaudeCredentials {
        if let cached = lock.withLock({ cachedLocal }), !cached.isExpired {
            lock.withLock { lastLoadWasLocal = true }
            return cached
        }
        if let credentials = try? await local.load() {
            lock.withLock {
                lastLoadWasLocal = true
                cachedLocal = credentials
            }
            return credentials
        }
        let credentials = try await fallback.load()
        lock.withLock { lastLoadWasLocal = false }
        return credentials
    }

    public func save(_ credentials: ClaudeCredentials) async throws {
        try await fallback.save(credentials)
    }

    public func clear() throws {
        lock.withLock { cachedLocal = nil }
        try fallback.clear()
    }
}
#endif
