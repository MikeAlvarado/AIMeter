import XCTest
@testable import UsageKit

final class ClaudeProviderTests: XCTestCase {
    func testFetchUsageSuccess() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        let source = StubCredentialSource(credentials: .valid, allowsRefresh: true)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.providerID, "claude")
        XCTAssertEqual(snapshot.planName, "pro")
        XCTAssertEqual(snapshot.windows.count, 2)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("claude-code/"), true)
    }

    func testExpiredTokenIsRefreshedBeforeFetch() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (200, Self.refreshBody),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        let source = StubCredentialSource(credentials: .expired, allowsRefresh: true)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        _ = try await provider.fetchUsage()

        let usageRequest = try XCTUnwrap(
            transport.requests.first { $0.url == ClaudeProvider.usageEndpoint }
        )
        XCTAssertEqual(usageRequest.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
        XCTAssertEqual(source.saved.last?.accessToken, "new-token")
        // Rotated refresh token persisted alongside the new access token.
        XCTAssertEqual(source.saved.last?.refreshToken, "new-refresh")
    }

    func test401TriggersOneRefreshAndRetry() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (200, Self.refreshBody),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (401, "{}"),
            (200, Self.usageBody),
        ])
        let source = StubCredentialSource(credentials: .valid, allowsRefresh: true)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.windows.count, 2)
        let usageRequests = transport.requests.filter { $0.url == ClaudeProvider.usageEndpoint }
        XCTAssertEqual(usageRequests.count, 2)
        XCTAssertEqual(usageRequests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
    }

    func testExpiredTokenWithoutRefreshThrowsTokenExpired() async {
        let transport = StubTransport()
        let source = StubCredentialSource(credentials: .expired, allowsRefresh: false)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        await assertThrows(UsageError.tokenExpired) {
            _ = try await provider.fetchUsage()
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func test401WithoutRefreshThrowsNotAuthenticated() async {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (401, "{}"),
        ])
        let source = StubCredentialSource(credentials: .valid, allowsRefresh: false)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        await assertThrows(UsageError.notAuthenticated) {
            _ = try await provider.fetchUsage()
        }
    }

    func test429ThrowsRateLimitedWithRetryAfter() async {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (429, "{}", ["Retry-After": "30"]),
        ])
        let source = StubCredentialSource(credentials: .valid, allowsRefresh: false)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        await assertThrows(UsageError.rateLimited(retryAfter: 30, body: "{}")) {
            _ = try await provider.fetchUsage()
        }
    }

    func testEmptyWindowsThrowsInvalidResponse() async {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, "{}"),
        ])
        let source = StubCredentialSource(credentials: .valid, allowsRefresh: false)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        do {
            _ = try await provider.fetchUsage()
            XCTFail("expected invalidResponse")
        } catch let error as UsageError {
            guard case .invalidResponse = error else {
                return XCTFail("expected invalidResponse, got \(error)")
            }
        } catch {
            XCTFail("expected UsageError, got \(error)")
        }
    }

    private func assertThrows(
        _ expected: UsageError,
        _ body: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as UsageError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected UsageError, got \(error)", file: file, line: line)
        }
    }

    func testMissingSubscriptionResolvedFromProfileAndPersisted() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.route(url: ClaudeProvider.profileEndpoint, responses: [
            (200, #"{"account": {"has_claude_pro": false, "has_claude_max": true}}"#),
        ])
        let source = StubCredentialSource(credentials: .withoutSubscription, allowsRefresh: true)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.planName, "max")
        // Persisted so the next fetch skips the profile call.
        XCTAssertEqual(source.saved.last?.subscriptionType, "max")
    }

    func testStoredSubscriptionSkipsProfileCall() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        let source = StubCredentialSource(credentials: .valid, allowsRefresh: true)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.planName, "pro")
        XCTAssertFalse(transport.requests.contains { $0.url == ClaudeProvider.profileEndpoint })
    }

    private static let usageBody = """
    {
      "limits": [
        {"kind": "session", "percent": 24, "resets_at": "2026-07-17T05:59:59.620269+00:00"},
        {"kind": "weekly_all", "percent": 14, "resets_at": "2026-07-19T23:59:59.620295+00:00"}
      ]
    }
    """

    private static let refreshBody = """
    {"access_token": "new-token", "refresh_token": "new-refresh", "expires_in": 28800}
    """
}

// MARK: - Stubs

private extension ClaudeCredentials {
    static let valid = ClaudeCredentials(
        accessToken: "valid-token",
        refreshToken: "refresh-token",
        expiresAt: Date(timeIntervalSinceNow: 3600),
        subscriptionType: "pro"
    )

    static let expired = ClaudeCredentials(
        accessToken: "old-token",
        refreshToken: "refresh-token",
        expiresAt: Date(timeIntervalSinceNow: -60),
        subscriptionType: "pro"
    )

    /// An in-app OAuth connection made before the exchange captured the
    /// subscription — the case the profile fallback exists for.
    static let withoutSubscription = ClaudeCredentials(
        accessToken: "valid-token",
        refreshToken: "refresh-token",
        expiresAt: Date(timeIntervalSinceNow: 3600)
    )
}

private final class StubCredentialSource: ClaudeCredentialSource, @unchecked Sendable {
    let allowsRefresh: Bool
    private(set) var saved: [ClaudeCredentials] = []
    private var credentials: ClaudeCredentials

    init(credentials: ClaudeCredentials, allowsRefresh: Bool) {
        self.credentials = credentials
        self.allowsRefresh = allowsRefresh
    }

    func load() async throws -> ClaudeCredentials {
        credentials
    }

    func save(_ credentials: ClaudeCredentials) async throws {
        saved.append(credentials)
        self.credentials = credentials
    }
}

private final class StubTransport: HTTPTransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private var routes: [URL: [(status: Int, body: String, headers: [String: String])]] = [:]

    func route(url: URL, responses: [(Int, String)]) {
        routes[url] = responses.map { ($0.0, $0.1, [:]) }
    }

    func route(url: URL, responses: [(Int, String, [String: String])]) {
        routes[url] = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard let url = request.url, let queue = routes[url], !queue.isEmpty else {
            throw UsageError.invalidResponse("no stubbed response for \(request.url?.absoluteString ?? "nil")")
        }
        // Consume responses in order; the last one repeats.
        let next = queue[0]
        if queue.count > 1 {
            routes[url] = Array(queue.dropFirst())
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: next.status,
            httpVersion: nil,
            headerFields: next.headers
        )!
        return (Data(next.body.utf8), response)
    }
}
