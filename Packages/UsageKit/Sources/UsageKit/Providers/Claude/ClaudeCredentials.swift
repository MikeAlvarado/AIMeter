import Foundation

/// OAuth credentials in the shape Claude Code maintains them
/// (Keychain item "Claude Code-credentials" or ~/.claude/.credentials.json).
public struct ClaudeCredentials: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
    public var scopes: [String]
    /// e.g. "pro", "max".
    public var subscriptionType: String?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        scopes: [String] = [],
        subscriptionType: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.subscriptionType = subscriptionType
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    /// Parses the JSON document Claude Code writes:
    /// `{"claudeAiOauth": {"accessToken": ..., "expiresAt": <ms epoch>, ...}}`.
    /// A bare `claudeAiOauth` object (no wrapper) is accepted too, so users
    /// can paste either form on iOS.
    public static func fromClaudeCodeJSON(_ data: Data) throws -> ClaudeCredentials {
        let decoder = JSONDecoder()
        let payload: ClaudeCodeOAuthPayload
        if let wrapped = try? decoder.decode(ClaudeCodeCredentialsFile.self, from: data) {
            payload = wrapped.claudeAiOauth
        } else if let bare = try? decoder.decode(ClaudeCodeOAuthPayload.self, from: data) {
            payload = bare
        } else {
            throw UsageError.invalidResponse("unrecognized Claude Code credentials format")
        }
        return ClaudeCredentials(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiresAt: payload.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            scopes: payload.scopes ?? [],
            subscriptionType: payload.subscriptionType
        )
    }
}

private struct ClaudeCodeCredentialsFile: Decodable {
    let claudeAiOauth: ClaudeCodeOAuthPayload
}

private struct ClaudeCodeOAuthPayload: Decodable {
    let accessToken: String
    let refreshToken: String?
    /// Milliseconds since epoch.
    let expiresAt: Double?
    let scopes: [String]?
    let subscriptionType: String?
}

/// Where `ClaudeProvider` obtains credentials and persists rotated tokens.
public protocol ClaudeCredentialSource: Sendable {
    /// Whether the provider may refresh the token and persist the rotated
    /// credentials through this source. Sources that mirror Claude Code's
    /// own credentials must return false: Claude Code owns that refresh
    /// cycle, and rotating its refresh token out from under it would log
    /// the user out of the CLI.
    var allowsRefresh: Bool { get }
    func load() async throws -> ClaudeCredentials
    func save(_ credentials: ClaudeCredentials) async throws
}
