import Foundation

/// A Codex login: the ChatGPT OAuth tokens the Codex CLI keeps in
/// `~/.codex/auth.json` (`tokens.access_token`, `refresh_token`,
/// `id_token`, `account_id`) and that the in-app device-code sign-in
/// mints. The access token is a JWT whose `exp` claim is the only expiry
/// there is; `auth.json` carries none.
public struct CodexCredentials: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var idToken: String?
    /// The ChatGPT account the usage belongs to (a workspace, or the
    /// personal account), sent as the `ChatGPT-Account-Id` header the
    /// way the CLI sends it; also the login's cross-device identity.
    public var accountID: String?
    /// The access token's `exp` claim.
    public var expiresAt: Date?
    /// When the pair was last rotated, as the CLI records it.
    public var lastRefresh: Date?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        idToken: String? = nil,
        accountID: String? = nil,
        expiresAt: Date? = nil,
        lastRefresh: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.accountID = accountID
        self.expiresAt = expiresAt
        self.lastRefresh = lastRefresh
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    /// Parses the file `codex login` writes:
    /// `{"OPENAI_API_KEY": null, "tokens": {...}, "last_refresh": "..."}`.
    /// A file with no tokens (an API-key login, or logged out) is not a
    /// login.
    public static func fromAuthJSON(_ data: Data) throws -> CodexCredentials {
        let file: AuthFile
        do {
            file = try JSONDecoder().decode(AuthFile.self, from: data)
        } catch {
            throw UsageError.invalidResponse("unrecognized Codex auth.json format")
        }
        guard let tokens = file.tokens, let accessToken = tokens.accessToken, !accessToken.isEmpty else {
            throw UsageError.credentialsNotFound("Codex is signed in with an API key, or signed out")
        }
        let claims = JWTClaims(token: accessToken)
        return CodexCredentials(
            accessToken: accessToken,
            refreshToken: tokens.refreshToken,
            idToken: tokens.idToken,
            accountID: tokens.accountID ?? claims?.accountID,
            expiresAt: claims?.expiresAt,
            lastRefresh: file.lastRefresh.flatMap(Self.parseDate)
        )
    }

    /// ISO 8601 with fractional seconds, as the CLI writes `last_refresh`.
    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private struct AuthFile: Decodable {
        let tokens: Tokens?
        let lastRefresh: String?

        enum CodingKeys: String, CodingKey {
            case tokens
            case lastRefresh = "last_refresh"
        }
    }

    private struct Tokens: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let idToken: String?
        let accountID: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case accountID = "account_id"
        }
    }
}

/// The two claims read from OpenAI's tokens, and nothing else: the
/// expiry, and the account id under the `https://api.openai.com/auth`
/// namespace (the email beside it is never decoded). No signature check:
/// these are the app's own tokens, read for their dates.
struct JWTClaims {
    let expiresAt: Date?
    let accountID: String?
    let planType: String?

    init?(token: String) {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        expiresAt = claims.exp.map { Date(timeIntervalSince1970: $0) }
        accountID = claims.auth?.accountID
        planType = claims.auth?.planType
    }

    private struct Payload: Decodable {
        let exp: Double?
        let auth: Auth?

        enum CodingKeys: String, CodingKey {
            case exp
            case auth = "https://api.openai.com/auth"
        }
    }

    private struct Auth: Decodable {
        let accountID: String?
        let planType: String?

        enum CodingKeys: String, CodingKey {
            case accountID = "chatgpt_account_id"
            case planType = "chatgpt_plan_type"
        }
    }
}

/// Where `CodexProvider` obtains credentials and persists rotated tokens.
public protocol CodexCredentialSource: CredentialStore {
    /// Whether the provider may refresh the token and persist the rotated
    /// pair through this source. The macOS mirror of the Codex CLI's own
    /// file returns false: the CLI owns that refresh cycle, and OpenAI
    /// rotates the refresh token on use, so rotating it from here would
    /// log the CLI out.
    var allowsRefresh: Bool { get }
    func load() async throws -> CodexCredentials
    func save(_ credentials: CodexCredentials) async throws
}
