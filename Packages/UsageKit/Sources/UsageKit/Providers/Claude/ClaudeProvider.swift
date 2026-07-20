import Foundation

/// Fetches Claude Pro/Max usage from the undocumented endpoint Claude Code
/// uses internally. All endpoint specifics live here and in
/// `ClaudeUsageResponse` so a breaking change touches one place.
public struct ClaudeProvider: UsageProvider {
    static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let profileEndpoint = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    public let id = "claude"
    public let displayName = "Claude"

    private let credentialSource: any ClaudeCredentialSource
    private let transport: any HTTPTransport
    private let userAgent: String

    /// - Parameter userAgent: sent as `User-Agent`. Must look like a Claude
    ///   Code client (`claude-code/<version>`); other agents hit an
    ///   aggressively rate-limited bucket and get persistent 429s.
    public init(
        credentialSource: any ClaudeCredentialSource,
        transport: any HTTPTransport = URLSessionTransport(),
        userAgent: String = "claude-code/2.1.212"
    ) {
        self.credentialSource = credentialSource
        self.transport = transport
        self.userAgent = userAgent
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        var credentials = try await credentialSource.load()

        if credentials.isExpired {
            credentials = try await refreshed(credentials)
        }

        var (data, response) = try await send(with: credentials)

        if response.statusCode == 401, credentialSource.allowsRefresh {
            credentials = try await refreshed(credentials)
            (data, response) = try await send(with: credentials)
        }

        switch response.statusCode {
        case 200:
            break
        case 401:
            throw UsageError.notAuthenticated
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            throw UsageError.rateLimited(retryAfter: retryAfter, body: Self.errorBody(data))
        default:
            throw UsageError.httpError(statusCode: response.statusCode, body: Self.errorBody(data))
        }

        let decoded: ClaudeUsageResponse
        do {
            decoded = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        } catch {
            throw UsageError.invalidResponse("usage decode: \(error.localizedDescription)")
        }

        let windows = decoded.usageWindows()
        guard !windows.isEmpty else {
            throw UsageError.invalidResponse("no usage windows in response")
        }

        return UsageSnapshot(
            providerID: id,
            planName: await planName(for: credentials),
            fetchedAt: Date(),
            windows: windows,
            spend: decoded.spendStatus(),
            extraUsage: decoded.extraUsageStatus()
        )
    }

    /// The stored subscription when present; otherwise resolved once from
    /// the profile endpoint and persisted so later fetches skip the extra
    /// call. Best-effort: a profile failure just leaves the plan unknown.
    private func planName(for credentials: ClaudeCredentials) async -> String? {
        if let subscription = credentials.subscriptionType {
            return subscription
        }
        guard let plan = try? await fetchProfilePlan(with: credentials) else {
            return nil
        }
        if credentialSource.allowsRefresh {
            var updated = credentials
            updated.subscriptionType = plan
            try? await credentialSource.save(updated)
        }
        return plan
    }

    private func fetchProfilePlan(with credentials: ClaudeCredentials) async throws -> String? {
        let (data, response) = try await transport.send(
            request(for: Self.profileEndpoint, credentials: credentials)
        )
        guard response.statusCode == 200 else { return nil }
        return try JSONDecoder().decode(ClaudeProfileResponse.self, from: data).subscriptionType
    }

    /// Raw response body attached to HTTP errors so the UI can show what
    /// the endpoint actually said; trimmed to keep error text bounded.
    private static func errorBody(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return String(text.prefix(400))
    }

    private func send(with credentials: ClaudeCredentials) async throws -> (Data, HTTPURLResponse) {
        try await transport.send(request(for: Self.usageEndpoint, credentials: credentials))
    }

    private func request(for url: URL, credentials: ClaudeCredentials) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func refreshed(_ credentials: ClaudeCredentials) async throws -> ClaudeCredentials {
        guard credentialSource.allowsRefresh else {
            // Read-only sources (macOS mirroring Claude Code) can't refresh;
            // the next load may pick up a token Claude Code refreshed itself.
            throw UsageError.tokenExpired
        }
        let updated = try await ClaudeOAuthClient(transport: transport).refresh(credentials)
        try await credentialSource.save(updated)
        return updated
    }
}
