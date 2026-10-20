import Foundation

/// OpenAI's token endpoint for the Codex CLI's public client: the
/// refresh (`CodexProvider`, app-owned sources only) and the exchange
/// the device-code sign-in ends with (`CodexDeviceAuth`). Form-encoded,
/// as the CLI sends it.
struct CodexOAuthClient: Sendable {
    static let issuer = URL(string: "https://auth.openai.com")!
    static let tokenEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    /// The Codex CLI's public OAuth client (PKCE, no secret).
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    var transport: any HTTPTransport

    func refresh(_ credentials: CodexCredentials) async throws -> CodexCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw UsageError.tokenExpired
        }
        let token = try await send([
            ("grant_type", "refresh_token"),
            ("client_id", Self.clientID),
            ("refresh_token", refreshToken),
        ])
        var updated = credentials
        updated.accessToken = token.accessToken
        updated.refreshToken = token.refreshToken ?? credentials.refreshToken
        updated.idToken = token.idToken ?? credentials.idToken
        updated.expiresAt = Self.expiry(of: token)
        updated.lastRefresh = Date()
        if let accountID = JWTClaims(token: token.accessToken)?.accountID {
            updated.accountID = accountID
        }
        return updated
    }

    /// The device-code flow's last step: the authorization code the poll
    /// returned, with the PKCE verifier the server minted for it.
    func exchange(authorizationCode: String, codeVerifier: String, redirectURI: String) async throws -> CodexCredentials {
        let token = try await send([
            ("grant_type", "authorization_code"),
            ("client_id", Self.clientID),
            ("code", authorizationCode),
            ("redirect_uri", redirectURI),
            ("code_verifier", codeVerifier),
        ])
        return CodexCredentials(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            idToken: token.idToken,
            accountID: JWTClaims(token: token.accessToken)?.accountID,
            expiresAt: Self.expiry(of: token),
            lastRefresh: Date()
        )
    }

    private func send(_ parameters: [(String, String)]) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.formEncoded(parameters).utf8)

        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            if response.statusCode == 429 {
                throw UsageError.rateLimited(
                    retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init),
                    body: Self.body(data)
                )
            }
            // A rejected grant means the login is gone for good (OpenAI
            // says so with a 400: `invalid_grant`, `refresh_token_expired`,
            // `refresh_token_reused`) or the client is (401). Any other
            // status says nothing about the login.
            if response.statusCode == 400 || response.statusCode == 401 {
                throw UsageError.notAuthenticated
            }
            throw UsageError.httpError(statusCode: response.statusCode, body: Self.body(data))
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw UsageError.invalidResponse("token endpoint: \(error.localizedDescription)")
        }
    }

    /// The access token's own `exp` claim, else the endpoint's
    /// `expires_in` from now.
    private static func expiry(of token: TokenResponse) -> Date? {
        JWTClaims(token: token.accessToken)?.expiresAt ?? token.expiresIn.map { Date(timeIntervalSinceNow: $0) }
    }

    static func formEncoded(_ parameters: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }

    /// Raw response text for error reporting, nil when there was none.
    static func body(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return String(text.prefix(400))
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresIn: Double?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
    }
}
