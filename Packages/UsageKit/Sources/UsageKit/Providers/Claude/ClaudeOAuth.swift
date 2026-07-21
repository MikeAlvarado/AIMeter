import Foundation
import CryptoKit

/// Interactive OAuth login (PKCE), mirroring Claude Code's own flow:
/// open the authorize page in a browser, the user approves and copies the
/// authentication code shown ("<code>#<state>"), we exchange it for tokens.
/// No client secret involved — PKCE protects the exchange.
public struct ClaudeOAuth: Sendable {
    /// One in-flight login attempt. The verifier/state pair must be kept
    /// until the pasted code comes back.
    public struct Session: Sendable {
        public let authorizeURL: URL
        public let codeVerifier: String
        public let state: String
    }

    static let authorizeEndpoint = URL(string: "https://claude.ai/oauth/authorize")!
    static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    /// user:profile is what the usage endpoint requires.
    static let scope = "user:profile user:inference"

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public static func startSession() -> Session {
        let verifier = randomURLSafeToken()
        let state = randomURLSafeToken()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()

        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: ClaudeOAuthClient.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return Session(authorizeURL: components.url!, codeVerifier: verifier, state: state)
    }

    /// Exchanges the code the user pasted. Accepts the raw "<code>#<state>"
    /// string from the callback page (whitespace tolerated).
    public func exchange(pastedCode: String, session: Session) async throws -> ClaudeCredentials {
        let trimmed = pastedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw UsageError.invalidResponse("empty authentication code")
        }
        let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        guard let code = parts.first, !code.isEmpty else {
            throw UsageError.invalidResponse("invalid authentication code")
        }

        var request = URLRequest(url: ClaudeOAuthClient.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ExchangeRequest(
            grantType: "authorization_code",
            code: code,
            state: parts.count > 1 ? parts[1] : session.state,
            clientId: ClaudeOAuthClient.clientID,
            redirectUri: Self.redirectURI,
            codeVerifier: session.codeVerifier
        ))

        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            if (400...499).contains(response.statusCode) {
                throw UsageError.notAuthenticated
            }
            throw UsageError.httpError(statusCode: response.statusCode, body: String(data: data, encoding: .utf8))
        }

        let token: TokenResponse
        do {
            token = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw UsageError.invalidResponse("token exchange: \(error.localizedDescription)")
        }

        return ClaudeCredentials(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.expiresIn.map { Date(timeIntervalSinceNow: $0) },
            scopes: token.scope?.components(separatedBy: " ") ?? [],
            subscriptionType: token.subscriptionType ?? token.account?.subscriptionType
        )
    }

    private static func randomURLSafeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max)
        }
        return Data(bytes).base64URLEncodedString()
    }
}

private struct ExchangeRequest: Encodable {
    let grantType: String
    let code: String
    let state: String
    let clientId: String
    let redirectUri: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case code
        case state
        case clientId = "client_id"
        case redirectUri = "redirect_uri"
        case codeVerifier = "code_verifier"
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double?
    let scope: String?
    /// Plan name ("pro", "max"), reported top-level or inside `account`
    /// depending on server version; both are optional so absence is fine.
    let subscriptionType: String?
    let account: Account?

    struct Account: Decodable {
        let subscriptionType: String?

        enum CodingKeys: String, CodingKey {
            case subscriptionType = "subscription_type"
        }
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case subscriptionType = "subscription_type"
        case scope, account
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
