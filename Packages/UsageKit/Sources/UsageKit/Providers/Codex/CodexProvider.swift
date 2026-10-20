import Foundation

/// Fetches a ChatGPT account's Codex limits from the endpoint the Codex
/// CLI reads for `/status`. All endpoint specifics live here and in
/// `CodexUsageResponse` so a server change touches one place; the login
/// itself is `CodexCredentials`, from the CLI's file on a Mac or the
/// in-app device-code sign-in.
public struct CodexProvider: UsageProvider {
    static let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    /// The provider *family* identifier every `ConnectedAccount.providerID`
    /// and `UsageSnapshot.providerID` of this provider carries — the one
    /// place the literal lives.
    public static let providerID = "codex"
    public static let providerDisplayName = "Codex"
    /// OpenAI's public status page, a Statuspage like Claude's.
    public static let statusSummaryEndpoint = URL(string: "https://status.openai.com/api/v2/summary.json")!
    public static let statusPageURL = URL(string: "https://status.openai.com")!

    public let id = CodexProvider.providerID
    public let displayName = CodexProvider.providerDisplayName

    private let credentialSource: any CodexCredentialSource
    private let transport: any HTTPTransport
    private let userAgent: String

    /// How long a rejected refresh waits before its last look at the
    /// store (see `rotate`). Tests set it to zero.
    var rejectionRecheckDelay: Duration = .milliseconds(1500)

    public init(
        credentialSource: any CodexCredentialSource,
        transport: any HTTPTransport = URLSessionTransport(),
        userAgent: String = "AIMeter"
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

        if response.statusCode == 401 {
            if credentialSource.allowsRefresh {
                credentials = try await refreshed(credentials)
                (data, response) = try await send(with: credentials)
            } else {
                credentialSource.invalidateCache()
            }
        }

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

        let decoded: CodexUsageResponse
        do {
            decoded = try CodexUsageResponse.decode(data)
        } catch {
            throw UsageError.invalidResponse("usage decode: \(error.localizedDescription)")
        }

        let windows = decoded.usageWindows()
        guard !windows.isEmpty else {
            throw UsageError.invalidResponse("no usage windows in response")
        }

        let accountID = decoded.accountId ?? credentials.accountID
        return UsageSnapshot(
            providerID: id,
            planName: decoded.planType,
            fetchedAt: Date(),
            windows: windows,
            spend: decoded.spendStatus(),
            accountIdentity: accountID.map { Self.identity(for: $0) }
        )
    }

    /// The cross-device identity of a login, from the ChatGPT account id.
    static func identity(for accountID: String) -> String {
        "\(providerID):\(accountID)"
    }

    /// Raw response body attached to HTTP errors so the UI can show what
    /// the endpoint actually said; trimmed to keep error text bounded.
    private static func errorBody(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return String(text.prefix(400))
    }

    private func send(with credentials: CodexCredentials) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: Self.usageEndpoint)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            // The workspace the usage is read for, the way the CLI asks.
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await transport.send(request)
    }

    private func refreshed(_ credentials: CodexCredentials) async throws -> CodexCredentials {
        guard credentialSource.allowsRefresh else {
            // The Mac's mirror of the CLI's file can't refresh; the CLI
            // rotates its own pair the next time it runs.
            throw UsageError.tokenExpired
        }
        // OpenAI spends the refresh token the moment it accepts it, so the
        // exchange and the save run in a task of their own, out of reach
        // of the caller's cancellation (see `ClaudeProvider`).
        let provider = self
        return try await Task {
            try await provider.rotate(credentials)
        }.value
    }

    /// The same rotation race as Claude's: on iOS the widget refreshes the
    /// same login against the same shared Keychain item, so a rejected
    /// refresh is first checked against what the store holds now.
    private func rotate(_ credentials: CodexCredentials) async throws -> CodexCredentials {
        let client = CodexOAuthClient(transport: transport)
        do {
            let updated = try await client.refresh(credentials)
            try await credentialSource.save(updated)
            return updated
        } catch UsageError.notAuthenticated {
            var latest = try await credentialSource.load()
            if latest.refreshToken == credentials.refreshToken {
                try await Task.sleep(for: rejectionRecheckDelay)
                latest = try await credentialSource.load()
            }
            guard latest.refreshToken != credentials.refreshToken else {
                throw UsageError.notAuthenticated
            }
            if !latest.isExpired {
                return latest
            }
            let updated = try await client.refresh(latest)
            try await credentialSource.save(updated)
            return updated
        }
    }
}
