import XCTest
@testable import UsageKit

/// `copilot-quota-response.json` is a real capture of a Free account
/// (`Scripts/probe-copilot-quota.sh -o`, 2026-10-20, ids redacted, the
/// user id replaced): chat and completions metered, premium requests
/// absent (`has_quota` false, entitlement 0), `copilot_plan`
/// "individual" beside the SKU that says Free.
final class CopilotResponseMappingTests: XCTestCase {
    func testFreeCaptureMetersChatAndCompletionsAndSkipsTheAbsentPremiumQuota() throws {
        let response = try JSONDecoder().decode(CopilotQuotaResponse.self, from: fixtureData("copilot-quota-response"))
        let windows = response.usageWindows()

        XCTAssertEqual(windows.map(\.kind), [.quota("chat"), .quota("completions")])
        XCTAssertEqual(windows[0].usedPct, 0)
        XCTAssertEqual(windows[1].usedPct, 0)
        let reset = try XCTUnwrap(windows[0].resetsAt)
        XCTAssertEqual(reset, Date(timeIntervalSince1970: 1_793_491_200), "2026-11-01 at midnight UTC")
        XCTAssertEqual(windows[0].duration, 31 * 86400, "October")
        XCTAssertEqual(response.planName, "Free", "the SKU, not copilot_plan's \"individual\"")
        XCTAssertEqual(response.id, 4242)
    }

    func testThePlanComesFromTheSKUFirst() throws {
        func plan(_ json: String) throws -> String? {
            try JSONDecoder().decode(CopilotQuotaResponse.self, from: Data(json.utf8)).planName
        }
        XCTAssertEqual(try plan(#"{"copilot_plan": "individual", "access_type_sku": "free_limited_copilot"}"#), "Free")
        XCTAssertEqual(try plan(#"{"copilot_plan": "individual", "access_type_sku": "copilot_for_individual"}"#), "Pro")
        XCTAssertEqual(try plan(#"{"copilot_plan": "individual_pro", "access_type_sku": "copilot_pro_plus"}"#), "Pro+")
        XCTAssertEqual(try plan(#"{"copilot_plan": "business", "access_type_sku": "copilot_for_business"}"#), "Business")
        XCTAssertEqual(try plan(#"{"copilot_plan": "individual_pro"}"#), "Pro+", "copilot_plan stands in without a SKU")
        XCTAssertEqual(try plan(#"{"copilot_plan": "something_new", "access_type_sku": "x"}"#), "something_new")
    }

    func testUnlimitedQuotasAreNotMeteredAndCountsStandInForTheMissingPercent() throws {
        let json = """
        {"copilot_plan": "individual", "quota_reset_date": "2026-03-01T00:00:00Z", "quota_snapshots": {
          "completions": {"entitlement": 0, "unlimited": true},
          "premium_interactions": {"entitlement": 300, "remaining": 60, "unlimited": false},
          "chat": {"entitlement": 0, "unlimited": true}}}
        """
        let response = try JSONDecoder().decode(CopilotQuotaResponse.self, from: Data(json.utf8))
        let windows = response.usageWindows()
        XCTAssertEqual(windows.map(\.kind), [.quota("premium_interactions")])
        XCTAssertEqual(windows[0].usedPct, 80)
        XCTAssertEqual(windows[0].duration, 28 * 86400, "February")
        XCTAssertEqual(response.planName, "Pro")
    }

    func testAFullQuotaIsExceededAndUnknownQuotasFollowTheKnownOnes() throws {
        let json = """
        {"copilot_plan": "individual_pro", "quota_reset_date": "2026-11-01", "quota_snapshots": {
          "zeta": {"entitlement": 10, "percent_remaining": 50, "unlimited": false},
          "premium_interactions": {"entitlement": 1500, "percent_remaining": 0, "unlimited": false}}}
        """
        let response = try JSONDecoder().decode(CopilotQuotaResponse.self, from: Data(json.utf8))
        let windows = response.usageWindows()
        XCTAssertEqual(windows.map(\.kind), [.quota("premium_interactions"), .quota("zeta")])
        XCTAssertEqual(windows[0].severity, .exceeded)
        XCTAssertEqual(response.planName, "Pro+")
    }
}

final class CopilotProviderTests: XCTestCase {
    func testFetchSendsTheTokenWithPlainHeadersAndKeepsTheUserIDTheAnswerCarries() async throws {
        let transport = RoutedTransport()
        transport.route(url: CopilotProvider.quotaEndpoint, responses: [(200, try fixtureBody("copilot-quota-response"))])
        let source = StubCopilotSource(credentials: CopilotCredentials(accessToken: "gho_x"))
        let provider = CopilotProvider(credentialSource: source, transport: transport)

        let first = try await provider.fetchUsage()
        let second = try await provider.fetchUsage()

        XCTAssertEqual(first.providerID, "copilot")
        XCTAssertEqual(first.planName, "Free")
        XCTAssertEqual(first.windows.count, 2)
        XCTAssertEqual(first.accountIdentity, "copilot:4242")
        XCTAssertEqual(second.accountIdentity, "copilot:4242")
        XCTAssertEqual(source.saved.count, 1, "the id is saved once, not on every fetch")
        XCTAssertEqual(source.saved.last?.userID, "4242")
        XCTAssertEqual(transport.requests.count, 2, "the quota endpoint and nothing else")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token gho_x")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Editor-Version"), "no editor headers needed")
    }

    func testStatusesMapToTypedErrors() async throws {
        let transport = RoutedTransport()
        transport.route(url: CopilotProvider.quotaEndpoint, responses: [
            (401, "{}", [:]), (429, "slow", ["Retry-After": "7"]), (403, "no copilot", [:]), (200, "{}", [:]),
        ])
        let provider = CopilotProvider(credentialSource: StubCopilotSource(credentials: CopilotCredentials(accessToken: "t")), transport: transport)
        await assertThrows(UsageError.notAuthenticated) { _ = try await provider.fetchUsage() }
        await assertThrows(UsageError.rateLimited(retryAfter: 7, body: "slow")) { _ = try await provider.fetchUsage() }
        await assertThrows(UsageError.httpError(statusCode: 403, body: "no copilot")) { _ = try await provider.fetchUsage() }
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
}

final class CopilotDeviceAuthTests: XCTestCase {
    func testRequestCodeAsksForNoScopeAndKeepsGitHubsTimings() async throws {
        let transport = RoutedTransport()
        transport.route(url: CopilotDeviceAuth.codeEndpoint, responses: [(200, """
        {"device_code": "dev-1", "user_code": "ABCD-1234", "verification_uri": "https://github.com/login/device", "expires_in": 899, "interval": 5}
        """)])
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        let code = try await CopilotDeviceAuth(transport: transport).requestCode(now: now)

        XCTAssertEqual(code.userCode, "ABCD-1234")
        XCTAssertEqual(code.verificationURL, URL(string: "https://github.com/login/device"))
        XCTAssertEqual(code.interval, 5)
        XCTAssertEqual(code.expiresAt, now.addingTimeInterval(899))
        let form = RoutedTransport.form(of: try XCTUnwrap(transport.requests.first))
        XCTAssertEqual(form["client_id"], CopilotDeviceAuth.clientID)
        XCTAssertNil(form["scope"], "no scope is asked for")
    }

    func testPollPendingSlowDownAuthorizedAndDenied() async throws {
        let transport = RoutedTransport()
        transport.route(url: CopilotDeviceAuth.tokenEndpoint, responses: [
            (200, #"{"error": "authorization_pending"}"#),
            (200, #"{"error": "slow_down", "interval": 10}"#),
            (200, #"{"access_token": "gho_new", "token_type": "bearer", "scope": ""}"#),
            (200, #"{"error": "access_denied"}"#),
        ])
        let auth = CopilotDeviceAuth(transport: transport)
        let code = CopilotDeviceAuth.Code(userCode: "X", verificationURL: URL(string: "https://github.com/login/device")!, interval: 5, expiresAt: .distantFuture, deviceCode: "dev-1")

        let first = try await auth.poll(code)
        XCTAssertEqual(first, .pending(interval: 5))
        let second = try await auth.poll(code)
        XCTAssertEqual(second, .pending(interval: 10))
        let third = try await auth.poll(code)
        XCTAssertEqual(third, .authorized(CopilotCredentials(accessToken: "gho_new")))
        do {
            _ = try await auth.poll(code)
            XCTFail("expected notAuthenticated")
        } catch let error as UsageError {
            XCTAssertEqual(error, .notAuthenticated)
        }
        let form = RoutedTransport.form(of: try XCTUnwrap(transport.requests.first))
        XCTAssertEqual(form["grant_type"], "urn:ietf:params:oauth:grant-type:device_code")
        XCTAssertEqual(form["device_code"], "dev-1")
    }
}

final class StatuspageSourceTests: XCTestCase {
    /// OpenAI's page carries no `incidents` key at all (2026-10-20).
    func testASummaryWithoutIncidentsIsOperational() throws {
        let body = #"{"page": {"name": "OpenAI"}, "status": {"indicator": "none", "description": "All Systems Operational"}, "components": [{"name": "Responses", "status": "operational"}]}"#
        let status = try StatuspageSource.parse(Data(body.utf8))
        XCTAssertEqual(status.indicator, .operational)
        XCTAssertTrue(status.affectedComponents.isEmpty)
        XCTAssertNil(status.incidentTitle)
    }

    func testEachProviderNamesItsOwnPage() {
        XCTAssertEqual(CodexProvider.statusSummaryEndpoint.host, "status.openai.com")
        XCTAssertEqual(CopilotProvider.statusSummaryEndpoint.host, "www.githubstatus.com")
        XCTAssertEqual(ClaudeStatusSource.summaryEndpoint.host, "status.claude.com")
    }
}

// MARK: - Stubs

private final class StubCopilotSource: CopilotCredentialSource, @unchecked Sendable {
    private(set) var saved: [CopilotCredentials] = []
    private var credentials: CopilotCredentials

    init(credentials: CopilotCredentials) {
        self.credentials = credentials
    }

    func load() async throws -> CopilotCredentials { credentials }

    func save(_ credentials: CopilotCredentials) async throws {
        saved.append(credentials)
        self.credentials = credentials
    }

    func clear() throws {}
}
