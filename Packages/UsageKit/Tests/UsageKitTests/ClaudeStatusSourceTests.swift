import XCTest
@testable import UsageKit

/// `status-summary-operational.json` is a real capture of
/// status.claude.com/api/v2/summary.json (2026-10-02, via
/// `Scripts/probe-status-endpoint.sh`); `status-summary-incident-synthetic.json`
/// is hand-built on the same Statuspage schema, since an incident can't be
/// captured on demand.
final class ClaudeStatusSourceTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testOperationalCaptureMapsToOperational() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let status = try ClaudeStatusSource.parse(fixture("status-summary-operational"), now: now)
        XCTAssertEqual(status.indicator, .operational)
        XCTAssertFalse(status.isDegraded)
        XCTAssertEqual(status.description, "All Systems Operational")
        XCTAssertTrue(status.affectedComponents.isEmpty)
        XCTAssertNil(status.incidentTitle)
        XCTAssertNil(status.incidentURL)
        XCTAssertEqual(status.checkedAt, now)
    }

    func testIncidentMapsIndicatorComponentsAndNewestIncident() throws {
        let status = try ClaudeStatusSource.parse(fixture("status-summary-incident-synthetic"))
        XCTAssertEqual(status.indicator, .major)
        XCTAssertTrue(status.isDegraded)
        XCTAssertEqual(status.description, "Partial System Outage")
        // Non-operational, in page order, and never the group container.
        XCTAssertEqual(status.affectedComponents, ["claude.ai", "Claude API (api.anthropic.com)"])
        XCTAssertEqual(status.incidentTitle, "Elevated error rates on the API")
        XCTAssertEqual(status.incidentURL, URL(string: "https://stspg.io/abc123"))
    }

    func testUnknownIndicatorIsUnknownNotDegraded() throws {
        let body = #"{"status":{"indicator":"purple","description":"?"},"components":[],"incidents":[]}"#
        let status = try ClaudeStatusSource.parse(Data(body.utf8))
        XCTAssertEqual(status.indicator, .unknown)
        XCTAssertFalse(status.isDegraded)
    }

    func testMaintenanceFallsBackToScheduledMaintenance() throws {
        let body = #"""
        {"status":{"indicator":"maintenance","description":"Service Under Maintenance"},
         "components":[{"name":"claude.ai","status":"under_maintenance","group":false}],
         "incidents":[],
         "scheduled_maintenances":[{"name":"Database upgrade","shortlink":"https://stspg.io/m1"}]}
        """#
        let status = try ClaudeStatusSource.parse(Data(body.utf8))
        XCTAssertEqual(status.indicator, .maintenance)
        XCTAssertTrue(status.isDegraded)
        XCTAssertEqual(status.affectedComponents, ["claude.ai"])
        XCTAssertEqual(status.incidentTitle, "Database upgrade")
        XCTAssertEqual(status.incidentURL, URL(string: "https://stspg.io/m1"))
    }

    func testMalformedBodyThrowsInvalidResponse() {
        XCTAssertThrowsError(try ClaudeStatusSource.parse(Data("<html>".utf8))) { error in
            guard case UsageError.invalidResponse = error else {
                return XCTFail("expected invalidResponse, got \(error)")
            }
        }
    }

    func testFetchSendsOneGETAndSurfacesHTTPErrors() async throws {
        let transport = StatusStubTransport(status: 503, body: "upstream")
        let source = ClaudeStatusSource(transport: transport)
        do {
            _ = try await source.fetchStatus()
            XCTFail("expected an error")
        } catch let error as UsageError {
            XCTAssertEqual(error, .httpError(statusCode: 503, body: "upstream"))
        }
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.url, ClaudeStatusSource.summaryEndpoint)
        XCTAssertEqual(transport.requests.first?.httpMethod, "GET")
    }

    func testFetchParsesASuccessfulBody() async throws {
        let transport = StatusStubTransport(status: 200, body: String(decoding: try fixture("status-summary-operational"), as: UTF8.self))
        let status = try await ClaudeStatusSource(transport: transport).fetchStatus()
        XCTAssertEqual(status.indicator, .operational)
    }

    // MARK: - Store

    func testStoreRoundTripsPerProvider() {
        let suite = "aimeter.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ServiceStatusStore(userDefaults: defaults)
        XCTAssertNil(store.status(for: "claude"))

        let status = ServiceStatus(
            indicator: .minor, description: "Minor Service Outage",
            affectedComponents: ["Claude Code"], incidentTitle: "Slow responses",
            incidentURL: URL(string: "https://stspg.io/x"), checkedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        store.save(status, for: "claude")
        XCTAssertEqual(store.status(for: "claude"), status)
        XCTAssertNil(store.status(for: "other"), "keyed per provider family")

        store.clear(for: "claude")
        XCTAssertNil(store.status(for: "claude"))
    }
}

private final class StatusStubTransport: HTTPTransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private let status: Int
    private let body: String

    init(status: Int, body: String) {
        self.status = status
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
