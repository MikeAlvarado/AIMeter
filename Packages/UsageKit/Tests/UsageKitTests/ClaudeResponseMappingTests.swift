import XCTest
@testable import UsageKit

/// Validates decoding against the real response captured by
/// Scripts/probe-usage-endpoint.sh in Phase 1 (Fixtures/claude-usage-response.json).
final class ClaudeResponseMappingTests: XCTestCase {
    func testDecodesRealFixtureIntoThreeWindows() throws {
        let response = try decodeFixture()
        let windows = response.usageWindows()

        XCTAssertEqual(windows.count, 3)

        let session = try XCTUnwrap(windows.first { $0.kind == .session })
        XCTAssertEqual(session.usedPct, 24)
        XCTAssertEqual(session.severity, .normal)
        XCTAssertEqual(session.isActive, true)
        XCTAssertNotNil(session.resetsAt)

        let weekly = try XCTUnwrap(windows.first { $0.kind == .weekly })
        XCTAssertEqual(weekly.usedPct, 14)
        XCTAssertEqual(weekly.isActive, false)

        let model = try XCTUnwrap(windows.first { $0.kind == .modelSpecific("Fable") })
        XCTAssertEqual(model.usedPct, 5)
        XCTAssertEqual(model.severity, .normal)
    }

    func testResetsAtParsesFractionalSecondsUTC() throws {
        let response = try decodeFixture()
        let session = try XCTUnwrap(response.usageWindows().first { $0.kind == .session })
        // Fixture: "2026-07-17T05:59:59.620269+00:00"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: try XCTUnwrap(session.resetsAt)
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 17)
        XCTAssertEqual(components.hour, 5)
        XCTAssertEqual(components.minute, 59)
        XCTAssertEqual(components.second, 59)
    }

    func testFallsBackToLegacyWindowsWhenLimitsMissing() throws {
        let json = """
        {
          "five_hour": {"utilization": 42.5, "resets_at": "2026-07-17T05:59:59+00:00"},
          "seven_day": {"utilization": 10.0, "resets_at": null}
        }
        """
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(json.utf8))
        let windows = response.usageWindows()

        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows.first { $0.kind == .session }?.usedPct, 42.5)
        XCTAssertEqual(windows.first { $0.kind == .weekly }?.usedPct, 10.0)
        XCTAssertNil(windows.first { $0.kind == .weekly }?.resetsAt)
    }

    func testSkipsUnknownLimitKindsAndScopelessScopedLimits() throws {
        let json = """
        {
          "limits": [
            {"kind": "session", "percent": 5, "resets_at": null},
            {"kind": "some_future_kind", "percent": 50, "resets_at": null},
            {"kind": "weekly_scoped", "percent": 50, "resets_at": null, "scope": {"model": null}}
          ]
        }
        """
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(json.utf8))
        let windows = response.usageWindows()

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].kind, .session)
    }

    private func decodeFixture() throws -> ClaudeUsageResponse {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "claude-usage-response",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        return try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(contentsOf: url))
    }
}
