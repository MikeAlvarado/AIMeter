import Foundation

/// Refreshes Claude OAuth tokens. Used only for credential sources the app
/// owns (e.g. a token pasted on iOS); never against Claude Code's own store.
struct ClaudeOAuthClient: Sendable {
    static let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    /// Public client ID of Claude Code's PKCE flow.
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    var transport: any HTTPTransport

    func refresh(_ credentials: ClaudeCredentials) async throws -> ClaudeCredentials {
        guard let refreshToken = credentials.refreshToken else {
            throw UsageError.tokenExpired
        }

        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RefreshRequest(
            grantType: "refresh_token",
            refreshToken: refreshToken,
            clientId: Self.clientID
        ))

        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            // A rejected refresh token means the login is gone for good.
            if (400...499).contains(response.statusCode) {
                throw UsageError.notAuthenticated
            }
            throw UsageError.httpError(statusCode: response.statusCode)
        }

        let refreshed: RefreshResponse
        do {
            refreshed = try JSONDecoder().decode(RefreshResponse.self, from: data)
        } catch {
            throw UsageError.invalidResponse("token refresh: \(error.localizedDescription)")
        }

        var updated = credentials
        updated.accessToken = refreshed.accessToken
        updated.refreshToken = refreshed.refreshToken ?? credentials.refreshToken
        updated.expiresAt = refreshed.expiresIn.map { Date(timeIntervalSinceNow: $0) }
        return updated
    }
}

private struct RefreshRequest: Encodable {
    let grantType: String
    let refreshToken: String
    let clientId: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case refreshToken = "refresh_token"
        case clientId = "client_id"
    }
}

private struct RefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
