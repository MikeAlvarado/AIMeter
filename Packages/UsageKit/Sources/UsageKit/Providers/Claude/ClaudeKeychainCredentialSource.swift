import Foundation

/// Credential source backed by the app's own Keychain. Used on iOS, where
/// the user pastes their Claude Code credentials once and the app then owns
/// the copy — including refreshing the token when it expires.
public struct ClaudeKeychainCredentialSource: ClaudeCredentialSource {
    public static let defaultKey = "claude.credentials"

    public var allowsRefresh: Bool { true }

    private let store: KeychainStore
    private let key: String

    public init(store: KeychainStore, key: String = ClaudeKeychainCredentialSource.defaultKey) {
        self.store = store
        self.key = key
    }

    public func load() async throws -> ClaudeCredentials {
        guard let credentials = try store.value(ClaudeCredentials.self, for: key) else {
            throw UsageError.credentialsNotFound("no Claude token stored yet")
        }
        return credentials
    }

    public func save(_ credentials: ClaudeCredentials) async throws {
        try store.set(credentials, for: key)
    }

    public func clear() throws {
        try store.delete(key)
    }
}
