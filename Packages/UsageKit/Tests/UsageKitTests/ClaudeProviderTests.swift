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

    func testRejectedRefreshUsesCredentialsRotatedElsewhere() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (400, "{}"),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        // The widget rotated the same login while this fetch was in
        // flight: the store now holds a different, still-valid pair.
        let source = StubCredentialSource(credentials: .expired, allowsRefresh: true)
        source.rotatesTo = .rotatedElsewhere
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.windows.count, 2)
        let usageRequest = try XCTUnwrap(transport.requests.first { $0.url == ClaudeProvider.usageEndpoint })
        XCTAssertEqual(usageRequest.value(forHTTPHeaderField: "Authorization"), "Bearer rotated-token")
        XCTAssertEqual(transport.requests.filter { $0.url == ClaudeOAuthClient.tokenEndpoint }.count, 1)
        // Nothing to write back: the winner's pair is already stored.
        XCTAssertTrue(source.saved.isEmpty)
    }

    func testRejectedRefreshWithUnchangedCredentialsThrowsNotAuthenticated() async {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (400, "{}"),
        ])
        let source = StubCredentialSource(credentials: .expired, allowsRefresh: true)
        var provider = ClaudeProvider(credentialSource: source, transport: transport)
        provider.rejectionRecheckDelay = .zero

        await assertThrows(UsageError.notAuthenticated) {
            _ = try await provider.fetchUsage()
        }
        XCTAssertTrue(transport.requests.allSatisfy { $0.url == ClaudeOAuthClient.tokenEndpoint })
    }

    /// The winner of a rotation race may save its new pair a moment after
    /// the loser's rejection; the loser's second look finds it.
    func testRejectedRefreshWaitsForARotationStillBeingSaved() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (400, "{}"),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        let source = StubCredentialSource(credentials: .expired, allowsRefresh: true)
        // Still the rejected pair right after the rejection (the fetch's
        // own load, then the first re-read); the winner's after that.
        source.rotatesTo = .rotatedElsewhere
        source.rotatesAfterLoad = 2
        var provider = ClaudeProvider(credentialSource: source, transport: transport)
        provider.rejectionRecheckDelay = .zero

        _ = try await provider.fetchUsage()

        let usageRequest = try XCTUnwrap(transport.requests.first { $0.url == ClaudeProvider.usageEndpoint })
        XCTAssertEqual(usageRequest.value(forHTTPHeaderField: "Authorization"), "Bearer rotated-token")
        XCTAssertTrue(source.saved.isEmpty)
    }

    /// Only a 400 or a 401 says the login is dead; a firewall's 403 says
    /// nothing about it and keeps its body for the UI.
    func testOtherTokenEndpointErrorsAreNotARejectedLogin() async {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (403, "blocked"),
        ])
        let source = StubCredentialSource(credentials: .expired, allowsRefresh: true)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        await assertThrows(UsageError.httpError(statusCode: 403, body: "blocked")) {
            _ = try await provider.fetchUsage()
        }
    }

    /// Anthropic spends the refresh token as soon as it accepts it, so a
    /// sweep cancelled mid-refresh must still store the new pair.
    func testCancelledFetchStillSavesTheRotatedPair() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (200, #"{"access_token": "new-token", "refresh_token": "new-refresh", "expires_in": 3600}"#),
        ])
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.delays[ClaudeOAuthClient.tokenEndpoint] = .milliseconds(200)
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        transport.onSend = { request in
            if request.url == ClaudeOAuthClient.tokenEndpoint { startedContinuation.yield() }
        }
        let source = StubCredentialSource(credentials: .expired, allowsRefresh: true)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let fetch = Task { try await provider.fetchUsage() }
        for await _ in started { break }
        fetch.cancel()
        _ = try? await fetch.value

        XCTAssertEqual(source.saved.first?.refreshToken, "new-refresh")
    }

    func testThrottledRefreshThrowsRateLimitedNotNotAuthenticated() async {
        let transport = StubTransport()
        transport.route(url: ClaudeOAuthClient.tokenEndpoint, responses: [
            (429, "", ["Retry-After": "30"]),
        ])
        let source = StubCredentialSource(credentials: .expired, allowsRefresh: true)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        await assertThrows(UsageError.rateLimited(retryAfter: 30, body: nil)) {
            _ = try await provider.fetchUsage()
        }
    }

    func test401WithoutRefreshInvalidatesTheSourceCache() async {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (401, "{}"),
        ])
        let source = StubCredentialSource(credentials: .valid, allowsRefresh: false)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        await assertThrows(UsageError.notAuthenticated) {
            _ = try await provider.fetchUsage()
        }
        XCTAssertEqual(source.invalidations, 1)
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

    /// The plan write-back must persist only `subscriptionType`, over
    /// whatever tokens are stored *now* — never over the ones this fetch
    /// loaded. Saving the stale pair would put an already-consumed refresh
    /// token back on top of a freshly rotated one, and Anthropic rejects a
    /// consumed refresh token for good.
    func testProfileWriteBackKeepsTokensRotatedMeanwhile() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.route(url: ClaudeProvider.profileEndpoint, responses: [
            (200, #"{"account": {"has_claude_pro": false, "has_claude_max": true}}"#),
        ])
        let source = StubCredentialSource(credentials: .withoutSubscription, allowsRefresh: true)
        // Another process (the iOS widget's own fetch) rotates the stored
        // token while this fetch is in flight.
        source.rotatesTo = ClaudeCredentials(
            accessToken: "rotated-token",
            refreshToken: "rotated-refresh",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        _ = try await provider.fetchUsage()

        let saved = try XCTUnwrap(source.saved.last)
        XCTAssertEqual(saved.subscriptionType, "max")
        XCTAssertEqual(saved.accessToken, "rotated-token")
        XCTAssertEqual(saved.refreshToken, "rotated-refresh")
    }

    /// A re-read that fails leaves nothing safe to write the plan over:
    /// the pair this fetch loaded may have been rotated since.
    func testProfileWriteBackSkippedWhenTheStoreCantBeRead() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.route(url: ClaudeProvider.profileEndpoint, responses: [
            (200, #"{"account": {"has_claude_pro": false, "has_claude_max": true}}"#),
        ])
        let source = StubCredentialSource(credentials: .withoutSubscription, allowsRefresh: true)
        source.failsLoadsAfter = 1
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.planName, "max")
        XCTAssertTrue(source.saved.isEmpty)
    }

    func testRecentlyCheckedSubscriptionSkipsProfileCall() async throws {
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

    /// The upgrade case: a plan cached at login stays cached forever unless
    /// something re-checks it, and the usage response never reports one — so
    /// a Pro → Max move would keep showing "Pro" everywhere the pill renders.
    func testStalePlanIsReverifiedAndPersisted() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.route(url: ClaudeProvider.profileEndpoint, responses: [
            (200, #"{"account": {"has_claude_pro": false, "has_claude_max": true}}"#),
        ])
        let source = StubCredentialSource(credentials: .stalePlan, allowsRefresh: true)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.planName, "max")
        XCTAssertEqual(source.saved.last?.subscriptionType, "max")
        let checkedAt = try XCTUnwrap(source.saved.last?.planCheckedAt)
        XCTAssertEqual(checkedAt.timeIntervalSinceNow, 0, accuracy: 5)
    }

    func testUnreachableProfileKeepsLastKnownPlan() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.route(url: ClaudeProvider.profileEndpoint, responses: [
            (500, "boom"),
        ])
        let source = StubCredentialSource(credentials: .stalePlan, allowsRefresh: true)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.planName, "pro")
        XCTAssertTrue(source.saved.isEmpty)
    }

    /// A read-only source (macOS mirroring Claude Code's own login) has
    /// nowhere to persist the check, so the resolved plan has to override
    /// the CLI item's stale one in memory — and not re-ask on every fetch.
    func testReadOnlySourceResolvesPlanOnceAndOverridesStoredOne() async throws {
        let transport = StubTransport()
        transport.route(url: ClaudeProvider.usageEndpoint, responses: [
            (200, Self.usageBody),
        ])
        transport.route(url: ClaudeProvider.profileEndpoint, responses: [
            (200, #"{"account": {"has_claude_pro": false, "has_claude_max": true}}"#),
        ])
        let source = StubCredentialSource(credentials: .stalePlan, allowsRefresh: false)
        let provider = ClaudeProvider(credentialSource: source, transport: transport)

        let first = try await provider.fetchUsage()
        let second = try await provider.fetchUsage()

        XCTAssertEqual(first.planName, "max")
        XCTAssertEqual(second.planName, "max")
        XCTAssertTrue(source.saved.isEmpty)
        XCTAssertEqual(transport.requests.filter { $0.url == ClaudeProvider.profileEndpoint }.count, 1)
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
        subscriptionType: "pro",
        planCheckedAt: Date()
    )

    static let expired = ClaudeCredentials(
        accessToken: "old-token",
        refreshToken: "refresh-token",
        expiresAt: Date(timeIntervalSinceNow: -60),
        subscriptionType: "pro",
        planCheckedAt: Date()
    )

    /// What the shared store holds after another process refreshed the
    /// same login: a different pair, still valid.
    static let rotatedElsewhere = ClaudeCredentials(
        accessToken: "rotated-token",
        refreshToken: "rotated-refresh",
        expiresAt: Date(timeIntervalSinceNow: 3600),
        subscriptionType: "pro",
        planCheckedAt: Date()
    )

    /// A plan cached longer ago than `planRecheckInterval` — or, with
    /// `planCheckedAt` nil, one cached by a build that never re-checked at
    /// all. Both are what an account that changed plan looks like.
    static let stalePlan = ClaudeCredentials(
        accessToken: "valid-token",
        refreshToken: "refresh-token",
        expiresAt: Date(timeIntervalSinceNow: 3600),
        subscriptionType: "pro",
        planCheckedAt: Date(timeIntervalSinceNow: -ClaudeProvider.planRecheckInterval - 60)
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
    private(set) var invalidations = 0
    private var credentials: ClaudeCredentials
    /// Replaces the stored credentials right after the first `load()`
    /// (or the `rotatesAfterLoad`th), standing in for another process
    /// rotating the token mid-fetch.
    var rotatesTo: ClaudeCredentials?
    var rotatesAfterLoad = 1
    /// Every `load()` past this many throws, like a Keychain that can't be
    /// read at that moment.
    var failsLoadsAfter: Int?
    private var loads = 0

    init(credentials: ClaudeCredentials, allowsRefresh: Bool) {
        self.credentials = credentials
        self.allowsRefresh = allowsRefresh
    }

    func load() async throws -> ClaudeCredentials {
        loads += 1
        if let failsLoadsAfter, loads > failsLoadsAfter {
            throw UsageError.credentialsNotFound("stub")
        }
        defer {
            if loads == rotatesAfterLoad, let rotated = rotatesTo {
                credentials = rotated
            }
        }
        return credentials
    }

    func save(_ credentials: ClaudeCredentials) async throws {
        saved.append(credentials)
        self.credentials = credentials
    }

    func invalidateCache() {
        invalidations += 1
    }

    func clear() throws {}
}

private final class StubTransport: HTTPTransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private var routes: [URL: [(status: Int, body: String, headers: [String: String])]] = [:]
    /// How long a request to the URL takes; a cancelled caller's request
    /// throws, the way URLSession's does.
    var delays: [URL: Duration] = [:]
    var onSend: (@Sendable (URLRequest) -> Void)?

    func route(url: URL, responses: [(Int, String)]) {
        routes[url] = responses.map { ($0.0, $0.1, [:]) }
    }

    func route(url: URL, responses: [(Int, String, [String: String])]) {
        routes[url] = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        onSend?(request)
        if let url = request.url, let delay = delays[url] {
            try await Task.sleep(for: delay)
        }
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
