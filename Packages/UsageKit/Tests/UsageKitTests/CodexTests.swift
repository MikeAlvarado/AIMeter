import XCTest
@testable import UsageKit

/// `codex-usage-response-free.json` is a real capture of a Free account
/// (`Scripts/probe-codex-usage.sh -o`, 2026-10-20, ids redacted);
/// `codex-usage-response-plus-synthetic.json` is hand-built on the CLI's
/// published schema for a paid plan (a session, a week, one
/// model-specific limit), since no paid account was at hand.
final class CodexResponseMappingTests: XCTestCase {
    func testFreeCaptureIsOneMonthlyWindowAndNoSession() throws {
        let response = try CodexUsageResponse.decode(fixtureData("codex-usage-response-free"))
        let windows = response.usageWindows()

        XCTAssertEqual(response.planType, "free")
        XCTAssertEqual(windows.count, 1)
        let month = try XCTUnwrap(windows.first)
        XCTAssertEqual(month.kind, .weekly, "the one overall allowance, whatever its length")
        XCTAssertEqual(month.usedPct, 0)
        XCTAssertEqual(month.duration, 30 * 86400)
        XCTAssertEqual(month.resetsAt, Date(timeIntervalSince1970: 1_795_119_565))
        XCTAssertNil(month.severity)
        XCTAssertNil(response.spendStatus(), "a personal plan has no spend control")
    }

    func testPaidShapeMapsSessionWeekAndTheModelLimitsWeeklyWindow() throws {
        let response = try CodexUsageResponse.decode(fixtureData("codex-usage-response-plus-synthetic"))
        let windows = response.usageWindows()

        XCTAssertEqual(windows.map(\.kind), [.session, .weekly, .modelSpecific("GPT-5.3-Codex-Spark")])
        XCTAssertEqual(windows[0].usedPct, 42)
        XCTAssertEqual(windows[0].duration, 5 * 3600)
        XCTAssertEqual(windows[0].resetsAt, Date(timeIntervalSince1970: 1_792_009_000))
        XCTAssertEqual(windows[1].usedPct, 17)
        XCTAssertEqual(windows[1].duration, 7 * 86400)
        XCTAssertEqual(windows[2].usedPct, 8, "the weekly one of the model's two windows")
        XCTAssertEqual(windows[2].duration, 7 * 86400)
        XCTAssertEqual(windows[2].resetsAt, windows[1].resetsAt)
    }

    func testReachedLimitMarksItsFullWindowExceeded() throws {
        let json = """
        {"plan_type": "plus", "rate_limit": {"allowed": false, "limit_reached": true,
          "primary_window": {"used_percent": 100, "limit_window_seconds": 18000, "reset_after_seconds": 100, "reset_at": 1792009000},
          "secondary_window": {"used_percent": 40, "limit_window_seconds": 604800, "reset_after_seconds": 1000, "reset_at": 1792300000}}}
        """
        let windows = try CodexUsageResponse.decode(Data(json.utf8)).usageWindows()
        XCTAssertEqual(windows.first { $0.kind == .session }?.severity, .exceeded)
        XCTAssertNil(windows.first { $0.kind == .weekly }?.severity)
    }

    func testResetFallsBackToResetAfterSecondsAndFiguresAreRequired() throws {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        let json = """
        {"plan_type": "plus", "rate_limit": {"allowed": true, "limit_reached": false,
          "primary_window": {"used_percent": 5, "limit_window_seconds": 18000, "reset_after_seconds": 600},
          "secondary_window": {"limit_window_seconds": 604800}}}
        """
        let windows = try CodexUsageResponse.decode(Data(json.utf8)).usageWindows(now: now)
        XCTAssertEqual(windows.count, 1, "a window with no figure is skipped")
        XCTAssertEqual(windows.first?.resetsAt, now.addingTimeInterval(600))
    }

    func testWorkspaceSpendLimitMapsToSpend() throws {
        let json = """
        {"plan_type": "team", "rate_limit": {"allowed": true, "limit_reached": false,
          "primary_window": {"used_percent": 5, "limit_window_seconds": 18000, "reset_after_seconds": 600, "reset_at": 1792009000}},
         "spend_control": {"reached": false, "individual_limit": {"limit": 50, "used": 12.5, "remaining_percent": 75, "reset_at": 1793000000}}}
        """
        let spend = try XCTUnwrap(CodexUsageResponse.decode(Data(json.utf8)).spendStatus())
        XCTAssertTrue(spend.enabled)
        XCTAssertEqual(spend.percent, 25)
        XCTAssertEqual(spend.usedAmount, 12.5)
        XCTAssertEqual(spend.limitAmount, 50)
        XCTAssertEqual(spend.currency, "USD")
    }
}

final class CodexCredentialsTests: XCTestCase {
    func testParsesTheCLIsAuthFileAndTheTokensClaims() throws {
        let token = fakeJWT([
            "exp": 1_800_000_000,
            "https://api.openai.com/auth": ["chatgpt_account_id": "acct-1", "chatgpt_plan_type": "free"],
        ])
        let json = """
        {"OPENAI_API_KEY": null, "tokens": {"id_token": "id.x.y", "access_token": "\(token)", "refresh_token": "rt-1", "account_id": "acct-1"},
         "last_refresh": "2026-10-20T20:14:43.310363Z"}
        """
        let credentials = try CodexCredentials.fromAuthJSON(Data(json.utf8))
        XCTAssertEqual(credentials.accessToken, token)
        XCTAssertEqual(credentials.refreshToken, "rt-1")
        XCTAssertEqual(credentials.idToken, "id.x.y")
        XCTAssertEqual(credentials.accountID, "acct-1")
        XCTAssertEqual(credentials.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(credentials.lastRefresh?.timeIntervalSince1970 ?? 0, 1_792_527_283.31, accuracy: 0.01)
        XCTAssertFalse(credentials.isExpired)
    }

    func testAnAPIKeyLoginOrASignedOutFileIsNotALogin() {
        let apiKey = #"{"OPENAI_API_KEY": "sk-x", "tokens": null, "last_refresh": null}"#
        XCTAssertThrowsError(try CodexCredentials.fromAuthJSON(Data(apiKey.utf8))) { error in
            guard case UsageError.credentialsNotFound = error else { return XCTFail("\(error)") }
        }
        let empty = #"{"tokens": {"access_token": "", "refresh_token": ""}}"#
        XCTAssertThrowsError(try CodexCredentials.fromAuthJSON(Data(empty.utf8)))
        XCTAssertThrowsError(try CodexCredentials.fromAuthJSON(Data("not json".utf8))) { error in
            guard case UsageError.invalidResponse = error else { return XCTFail("\(error)") }
        }
    }

    func testClaimsOfAnOpaqueTokenAreNil() {
        XCTAssertNil(JWTClaims(token: "opaque"))
        XCTAssertNil(JWTClaims(token: "a.b.c")?.expiresAt)
    }
}

final class CodexProviderTests: XCTestCase {
    func testFetchSendsTheCLIsHeadersAndMapsThePlanAndIdentity() async throws {
        let transport = RoutedTransport()
        transport.route(url: CodexProvider.usageEndpoint, responses: [(200, try fixtureBody("codex-usage-response-free"))])
        let source = StubCodexSource(credentials: .valid, allowsRefresh: true)
        let provider = CodexProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.providerID, "codex")
        XCTAssertEqual(snapshot.planName, "free")
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.accountIdentity, "codex:<redacted>", "the response's account id, as captured")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testExpiredTokenIsRefreshedBeforeFetchWithAFormBody() async throws {
        let transport = RoutedTransport()
        transport.route(url: CodexOAuthClient.tokenEndpoint, responses: [(200, Self.refreshBody)])
        transport.route(url: CodexProvider.usageEndpoint, responses: [(200, try fixtureBody("codex-usage-response-free"))])
        let source = StubCodexSource(credentials: .expired, allowsRefresh: true)
        let provider = CodexProvider(credentialSource: source, transport: transport)

        _ = try await provider.fetchUsage()

        let refresh = try XCTUnwrap(transport.requests(to: CodexOAuthClient.tokenEndpoint).first)
        XCTAssertEqual(refresh.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let form = RoutedTransport.form(of: refresh)
        XCTAssertEqual(form["grant_type"], "refresh_token")
        XCTAssertEqual(form["client_id"], CodexOAuthClient.clientID)
        XCTAssertEqual(form["refresh_token"], "refresh-token")
        let usage = try XCTUnwrap(transport.requests(to: CodexProvider.usageEndpoint).first)
        XCTAssertEqual(usage.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
        XCTAssertEqual(source.saved.last?.refreshToken, "new-refresh")
        XCTAssertEqual(source.saved.last?.accessToken, "new-token")
    }

    func test401TriggersOneRefreshAndRetry() async throws {
        let transport = RoutedTransport()
        transport.route(url: CodexOAuthClient.tokenEndpoint, responses: [(200, Self.refreshBody)])
        transport.route(url: CodexProvider.usageEndpoint, responses: [(401, "{}"), (200, try fixtureBody("codex-usage-response-free"))])
        let source = StubCodexSource(credentials: .valid, allowsRefresh: true)
        let provider = CodexProvider(credentialSource: source, transport: transport)

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(transport.requests(to: CodexProvider.usageEndpoint).count, 2)
    }

    func testTheMacsMirrorNeverRefreshes() async throws {
        let transport = RoutedTransport()
        let expired = StubCodexSource(credentials: .expired, allowsRefresh: false)
        await assertThrows(UsageError.tokenExpired) {
            _ = try await CodexProvider(credentialSource: expired, transport: transport).fetchUsage()
        }
        XCTAssertTrue(transport.requests.isEmpty)

        transport.route(url: CodexProvider.usageEndpoint, responses: [(401, "{}")])
        let rejected = StubCodexSource(credentials: .valid, allowsRefresh: false)
        await assertThrows(UsageError.notAuthenticated) {
            _ = try await CodexProvider(credentialSource: rejected, transport: transport).fetchUsage()
        }
        XCTAssertEqual(rejected.invalidations, 1)
    }

    func testRejectedRefreshUsesAPairRotatedElsewhere() async throws {
        let transport = RoutedTransport()
        transport.route(url: CodexOAuthClient.tokenEndpoint, responses: [(400, #"{"error": "refresh_token_reused"}"#)])
        transport.route(url: CodexProvider.usageEndpoint, responses: [(200, try fixtureBody("codex-usage-response-free"))])
        let source = StubCodexSource(credentials: .expired, allowsRefresh: true)
        source.rotatesTo = .rotatedElsewhere
        var provider = CodexProvider(credentialSource: source, transport: transport)
        provider.rejectionRecheckDelay = .zero

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(transport.requests(to: CodexProvider.usageEndpoint).first?.value(forHTTPHeaderField: "Authorization"), "Bearer rotated-token")
        XCTAssertTrue(source.saved.isEmpty)
    }

    func testRejectedRefreshWithUnchangedPairIsARejectedLogin() async {
        let transport = RoutedTransport()
        transport.route(url: CodexOAuthClient.tokenEndpoint, responses: [(400, "{}")])
        let source = StubCodexSource(credentials: .expired, allowsRefresh: true)
        var provider = CodexProvider(credentialSource: source, transport: transport)
        provider.rejectionRecheckDelay = .zero

        await assertThrows(UsageError.notAuthenticated) {
            _ = try await provider.fetchUsage()
        }
    }

    func test429AndOtherStatusesKeepTheirBodies() async throws {
        let transport = RoutedTransport()
        transport.route(url: CodexProvider.usageEndpoint, responses: [(429, "slow", ["Retry-After": "30"]), (503, "down", [:])])
        let provider = CodexProvider(credentialSource: StubCodexSource(credentials: .valid, allowsRefresh: false), transport: transport)
        await assertThrows(UsageError.rateLimited(retryAfter: 30, body: "slow")) { _ = try await provider.fetchUsage() }
        await assertThrows(UsageError.httpError(statusCode: 503, body: "down")) { _ = try await provider.fetchUsage() }
    }

    func testAResponseWithoutWindowsIsInvalid() async {
        let transport = RoutedTransport()
        transport.route(url: CodexProvider.usageEndpoint, responses: [(200, #"{"plan_type": "free", "rate_limit": null}"#)])
        let provider = CodexProvider(credentialSource: StubCodexSource(credentials: .valid, allowsRefresh: false), transport: transport)
        do {
            _ = try await provider.fetchUsage()
            XCTFail("expected invalidResponse")
        } catch let error as UsageError {
            guard case .invalidResponse = error else { return XCTFail("\(error)") }
        } catch {
            XCTFail("\(error)")
        }
    }

    private func fixtureBody(_ name: String) throws -> String {
        try XCTUnwrap(String(data: fixtureData(name), encoding: .utf8))
    }

    private func assertThrows(
        _ expected: UsageError, _ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line
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

    private static let refreshBody = #"{"access_token": "new-token", "refresh_token": "new-refresh", "id_token": "id.2", "expires_in": 864000}"#
}

final class CodexDeviceAuthTests: XCTestCase {
    func testRequestCodeReadsTheStringIntervalAndExpiry() async throws {
        let transport = RoutedTransport()
        transport.route(url: CodexDeviceAuth.usercodeEndpoint, responses: [(200, """
        {"device_auth_id": "deviceauth_1", "user_code": "83O4-A9V7A", "interval": "5", "expires_at": "2026-10-20T20:46:16.503422+00:00"}
        """)])
        let code = try await CodexDeviceAuth(transport: transport).requestCode()

        XCTAssertEqual(code.userCode, "83O4-A9V7A")
        XCTAssertEqual(code.interval, 5)
        XCTAssertEqual(code.verificationURL, URL(string: "https://auth.openai.com/codex/device"))
        XCTAssertEqual(code.expiresAt?.timeIntervalSince1970 ?? 0, 1_792_529_176.5, accuracy: 0.01)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: String]
        XCTAssertEqual(body, ["client_id": CodexOAuthClient.clientID])
    }

    func testPollIsNilUntilApprovedThenExchangesTheCode() async throws {
        let transport = RoutedTransport()
        transport.route(url: CodexDeviceAuth.tokenEndpoint, responses: [
            (403, ""),
            (200, #"{"authorization_code": "code-1", "code_challenge": "ch", "code_verifier": "ver-1"}"#),
        ])
        let token = fakeJWT(["exp": 1_800_000_000, "https://api.openai.com/auth": ["chatgpt_account_id": "acct-9"]])
        transport.route(url: CodexOAuthClient.tokenEndpoint, responses: [
            (200, #"{"access_token": "\#(token)", "refresh_token": "rt-9", "id_token": "id-9"}"#),
        ])
        let auth = CodexDeviceAuth(transport: transport)
        let code = CodexDeviceAuth.Code(userCode: "X", verificationURL: CodexDeviceAuth.verificationURL, interval: 5, expiresAt: nil, deviceAuthID: "deviceauth_1")

        let pending = try await auth.poll(code)
        XCTAssertNil(pending)

        let approved = try await auth.poll(code)
        let credentials = try XCTUnwrap(approved)
        XCTAssertEqual(credentials.refreshToken, "rt-9")
        XCTAssertEqual(credentials.accountID, "acct-9")
        XCTAssertEqual(credentials.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))
        let exchange = try XCTUnwrap(transport.requests(to: CodexOAuthClient.tokenEndpoint).first)
        let form = RoutedTransport.form(of: exchange)
        XCTAssertEqual(form["grant_type"], "authorization_code")
        XCTAssertEqual(form["code"], "code-1")
        XCTAssertEqual(form["code_verifier"], "ver-1")
        XCTAssertEqual(form["redirect_uri"], "https://auth.openai.com/deviceauth/callback")
    }

    func testAnUnexpectedPollStatusIsReported() async {
        let transport = RoutedTransport()
        transport.route(url: CodexDeviceAuth.tokenEndpoint, responses: [(500, "boom")])
        let code = CodexDeviceAuth.Code(userCode: "X", verificationURL: CodexDeviceAuth.verificationURL, interval: 5, expiresAt: nil, deviceAuthID: "d")
        do {
            _ = try await CodexDeviceAuth(transport: transport).poll(code)
            XCTFail("expected httpError")
        } catch let error as UsageError {
            XCTAssertEqual(error, .httpError(statusCode: 500, body: "boom"))
        } catch {
            XCTFail("\(error)")
        }
    }
}

// MARK: - Stubs

private extension CodexCredentials {
    static let valid = CodexCredentials(
        accessToken: "valid-token", refreshToken: "refresh-token", accountID: "acct-1",
        expiresAt: Date(timeIntervalSinceNow: 3600)
    )
    static let expired = CodexCredentials(
        accessToken: "old-token", refreshToken: "refresh-token", accountID: "acct-1",
        expiresAt: Date(timeIntervalSinceNow: -60)
    )
    static let rotatedElsewhere = CodexCredentials(
        accessToken: "rotated-token", refreshToken: "rotated-refresh", accountID: "acct-1",
        expiresAt: Date(timeIntervalSinceNow: 3600)
    )
}

private final class StubCodexSource: CodexCredentialSource, @unchecked Sendable {
    let allowsRefresh: Bool
    private(set) var saved: [CodexCredentials] = []
    private(set) var invalidations = 0
    private var credentials: CodexCredentials
    var rotatesTo: CodexCredentials?
    private var loads = 0

    init(credentials: CodexCredentials, allowsRefresh: Bool) {
        self.credentials = credentials
        self.allowsRefresh = allowsRefresh
    }

    func load() async throws -> CodexCredentials {
        loads += 1
        defer {
            if loads == 1, let rotated = rotatesTo { credentials = rotated }
        }
        return credentials
    }

    func save(_ credentials: CodexCredentials) async throws {
        saved.append(credentials)
        self.credentials = credentials
    }

    func invalidateCache() { invalidations += 1 }
    func clear() throws {}
}
