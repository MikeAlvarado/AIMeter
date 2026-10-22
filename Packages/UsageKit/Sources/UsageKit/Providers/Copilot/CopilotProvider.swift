import Foundation

/// Fetches a GitHub account's Copilot quotas from the endpoint Copilot's
/// editor plug-ins read. All endpoint specifics live here and in
/// `CopilotQuotaResponse`; the login is a GitHub OAuth token from the
/// device flow (`CopilotDeviceAuth`), which never expires on its own.
public struct CopilotProvider: UsageProvider {
    static let quotaEndpoint = URL(string: "https://api.github.com/copilot_internal/user")!

    /// The provider *family* identifier every `ConnectedAccount.providerID`
    /// and `UsageSnapshot.providerID` of this provider carries — the one
    /// place the literal lives.
    public static let providerID = "copilot"
    public static let providerDisplayName = "GitHub Copilot"
    /// GitHub's public status page, a Statuspage like Claude's; its
    /// "Copilot" components are the ones that matter here.
    public static let statusSummaryEndpoint = URL(string: "https://www.githubstatus.com/api/v2/summary.json")!
    public static let statusPageURL = URL(string: "https://www.githubstatus.com")!

    public let id = CopilotProvider.providerID
    public let displayName = CopilotProvider.providerDisplayName

    private let credentialSource: any CopilotCredentialSource
    private let transport: any HTTPTransport
    private let userAgent: String

    public init(
        credentialSource: any CopilotCredentialSource,
        transport: any HTTPTransport = URLSessionTransport(),
        userAgent: String = "AIMeter"
    ) {
        self.credentialSource = credentialSource
        self.transport = transport
        self.userAgent = userAgent
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        var credentials = try await credentialSource.load()
        // Plain headers: the endpoint answered them on 2026-10-20 without
        // any of the editor headers the plug-ins add.
        var request = URLRequest(url: Self.quotaEndpoint)
        request.setValue("token \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.send(request)

        switch response.statusCode {
        case 200:
            break
        case 401:
            throw UsageError.notAuthenticated
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw UsageError.rateLimited(retryAfter: retryAfter, body: Self.errorBody(data))
        default:
            throw UsageError.httpError(statusCode: response.statusCode, body: Self.errorBody(data))
        }

        let decoded: CopilotQuotaResponse
        do {
            decoded = try JSONDecoder().decode(CopilotQuotaResponse.self, from: data)
        } catch {
            throw UsageError.invalidResponse("quota decode: \(error.localizedDescription)")
        }

        let windows = decoded.usageWindows()
        // A GitHub account without Copilot: no quotas at all, and a SKU
        // that says so (measured 2026-10-21 on a login whose account had
        // no Copilot: `access_type_sku` "no_access", no `quota_snapshots`).
        if windows.isEmpty, decoded.hasNoCopilot {
            throw UsageError.noPlan(Self.providerDisplayName)
        }
        guard !windows.isEmpty else {
            // Says what came instead, quota fields only (the typed-errors
            // rule; the rest of the answer names the user).
            throw UsageError.invalidResponse("no metered quotas in response: \(decoded.quotaSummary)")
        }

        // The answer carries the user's id; kept with the login so the
        // identity outlives a response that ever leaves it out. A failed
        // save just means one more look next time.
        if let id = decoded.id, credentials.userID != String(id) {
            credentials.userID = String(id)
            try? await credentialSource.save(credentials)
        }

        return UsageSnapshot(
            providerID: id,
            planName: decoded.planName,
            fetchedAt: Date(),
            windows: windows,
            accountIdentity: credentials.userID.map { Self.identity(for: $0) }
        )
    }

    /// The cross-device identity of a login, from the GitHub user id.
    static func identity(for userID: String) -> String {
        "\(providerID):\(userID)"
    }

    private static func errorBody(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return String(text.prefix(400))
    }
}
