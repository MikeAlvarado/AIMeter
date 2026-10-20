import Foundation

/// A GitHub Copilot login: the GitHub OAuth token the device-code
/// sign-in mints (`CopilotDeviceAuth`), which does not expire on its own
/// (a revoked one is a 401), and the GitHub user's id once read, the
/// login's cross-device identity.
public struct CopilotCredentials: Codable, Equatable, Sendable {
    public var accessToken: String
    /// The GitHub user id (`GET /user`, its numeric `id` as text),
    /// read once after the sign-in.
    public var userID: String?

    public init(accessToken: String, userID: String? = nil) {
        self.accessToken = accessToken
        self.userID = userID
    }
}

/// Where `CopilotProvider` obtains the login and persists the user id.
public protocol CopilotCredentialSource: CredentialStore {
    func load() async throws -> CopilotCredentials
    func save(_ credentials: CopilotCredentials) async throws
}

/// The app's own copy of a Copilot login, in the app's Keychain (the
/// shared access group on iOS, so the widget can fetch with it).
public struct CopilotKeychainCredentialSource: CopilotCredentialSource {
    public static func storageKey(for accountID: String) -> String {
        "copilot.credentials.\(accountID)"
    }

    private let store: KeychainStore
    private let key: String

    public init(store: KeychainStore, key: String) {
        self.store = store
        self.key = key
    }

    public func load() async throws -> CopilotCredentials {
        guard let credentials = try store.value(CopilotCredentials.self, for: key) else {
            throw UsageError.credentialsNotFound("no GitHub token stored yet")
        }
        return credentials
    }

    public func save(_ credentials: CopilotCredentials) async throws {
        try store.set(credentials, for: key)
    }

    public func clear() throws {
        try store.delete(key)
    }
}
