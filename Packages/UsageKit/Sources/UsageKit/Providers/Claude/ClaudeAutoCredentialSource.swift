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

    public var allowsRefresh: Bool {
        lock.withLock { !lastLoadWasLocal }
    }

    public init(store: KeychainStore) {
        fallback = ClaudeKeychainCredentialSource(store: store)
    }

    public func load() async throws -> ClaudeCredentials {
        if let credentials = try? await local.load() {
            lock.withLock { lastLoadWasLocal = true }
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
        try fallback.clear()
    }
}
#endif
