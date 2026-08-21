import Foundation

/// Fetches Claude Pro/Max usage from the undocumented endpoint Claude Code
/// uses internally. All endpoint specifics live here and in
/// `ClaudeUsageResponse` so a breaking change touches one place.
public struct ClaudeProvider: UsageProvider {
    static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let profileEndpoint = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    public let id = "claude"
    public let displayName = "Claude"

    /// How long a resolved plan is trusted before it's re-verified against
    /// the profile endpoint. The plan is the one part of a snapshot that
    /// isn't re-derived on every fetch — the usage response carries no
    /// subscription field, so it's cached in the credentials — and a
    /// subscription changes whenever the user upgrades or downgrades. A
    /// cache with no expiry keeps showing "Pro" forever after a move to
    /// Max, so it gets one: at most four extra profile calls a day.
    static let planRecheckInterval: TimeInterval = 6 * 60 * 60

    private let credentialSource: any ClaudeCredentialSource
    private let transport: any HTTPTransport
    private let userAgent: String
    private let planCache = PlanCache()

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

    /// The stored subscription while it's still within
    /// `planRecheckInterval`; otherwise re-resolved from the profile
    /// endpoint and persisted, so later fetches skip the extra call until
    /// it goes stale again. Best-effort: a profile failure keeps the last
    /// plan we knew rather than blanking it.
    ///
    /// The write-back re-reads the source instead of saving the
    /// `credentials` value this fetch started with, and that matters: only
    /// `subscriptionType`/`planCheckedAt` are ours to persist here, while
    /// the token fields may have been rotated in the meantime by a
    /// concurrent fetch (on iOS the widget refreshes itself alongside the
    /// app, against the same shared Keychain item). Saving the whole stale
    /// value would put a consumed refresh token back over the fresh one —
    /// and Anthropic rejects a consumed refresh token permanently, which
    /// bricks the account until the user signs in again.
    private func planName(for credentials: ClaudeCredentials) async -> String? {
        if let cached = planCache.plan(checkedWithin: Self.planRecheckInterval) {
            return cached
        }
        if let subscription = credentials.subscriptionType,
           let checkedAt = credentials.planCheckedAt,
           Date().timeIntervalSince(checkedAt) < Self.planRecheckInterval {
            return subscription
        }
        guard let plan = try? await fetchProfilePlan(with: credentials) else {
            // Unreachable profile — or one that reports no subscription at
            // all, which is also what a shape change would look like. Keep
            // the last plan we knew instead of dropping the pill over it.
            return planCache.lastKnown ?? credentials.subscriptionType
        }
        planCache.record(plan)
        if credentialSource.allowsRefresh {
            var latest = (try? await credentialSource.load()) ?? credentials
            latest.subscriptionType = plan
            latest.planCheckedAt = Date()
            try? await credentialSource.save(latest)
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

/// The plan last resolved from the profile endpoint, remembered for the
/// lifetime of one provider instance.
///
/// Sources the app owns persist the same thing in the credentials
/// (`planCheckedAt`), which survives relaunches. The macOS mirror of Claude
/// Code's own login can't be written to at all — `allowsRefresh` is false —
/// so without this in-memory copy that account would re-fetch the profile on
/// every single refresh, and would keep reporting the CLI item's own stale
/// `subscriptionType` in between.
private final class PlanCache: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved: String?
    private var checkedAt: Date?

    /// The last resolved plan, if it was checked within `interval`.
    func plan(checkedWithin interval: TimeInterval) -> String? {
        lock.withLock {
            guard let checkedAt, Date().timeIntervalSince(checkedAt) < interval else { return nil }
            return resolved
        }
    }

    /// The last resolved plan whatever its age — the fallback when a
    /// re-check can't be completed.
    var lastKnown: String? {
        lock.withLock { resolved }
    }

    func record(_ plan: String) {
        lock.withLock {
            resolved = plan
            checkedAt = Date()
        }
    }
}
