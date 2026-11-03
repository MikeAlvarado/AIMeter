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
        // Scoped weekly windows share the weekly reset date exactly.
        XCTAssertEqual(model.resetsAt, weekly.resetsAt)
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

    func testDecodesSpendAndExtraUsageFromFixture() throws {
        let response = try decodeFixture()

        let spend = try XCTUnwrap(response.spendStatus())
        XCTAssertTrue(spend.enabled)
        XCTAssertEqual(spend.percent, 36)
        XCTAssertEqual(spend.severity, .normal)
        XCTAssertEqual(spend.usedAmount, 10.76)
        XCTAssertEqual(spend.limitAmount, 30.0)
        XCTAssertEqual(spend.currency, "USD")

        let extra = try XCTUnwrap(response.extraUsageStatus())
        XCTAssertTrue(extra.enabled)
        XCTAssertEqual(extra.usedCredits, 10.76)
        XCTAssertEqual(extra.monthlyLimit, 30.0)
        XCTAssertEqual(try XCTUnwrap(extra.utilization), 35.87, accuracy: 0.01)
        XCTAssertEqual(extra.currency, "USD")
    }

    func testMissingSpendAndExtraUsageMapToNil() throws {
        let json = """
        {"limits": [{"kind": "session", "percent": 10, "resets_at": null}]}
        """
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(json.utf8))
        XCTAssertNil(response.spendStatus())
        XCTAssertNil(response.extraUsageStatus())
    }

    /// Ultra (the old Max 20x, renamed 2026-10-30) has no 5-hour limit:
    /// captured on 2026-11-03, `five_hour` is null and `limits` carries the
    /// week and Fable's week alone, so the account shows those two and no
    /// session placeholder.
    func testUltraHasNoSessionWindow() throws {
        let windows = try decodeFixture("claude-usage-response-ultra").usageWindows()

        XCTAssertEqual(windows.map(\.kind), [.weekly, .modelSpecific("Fable")])
        XCTAssertEqual(windows.first?.usedPct, 9)
        XCTAssertEqual(windows.last?.resetsAt, windows.first?.resetsAt)
    }

    /// The week divided by app, in the order and with the names the
    /// endpoint sends (captured on the Ultra account, 2026-11-03).
    func testBreakdownMapsTheWeekByApp() throws {
        let breakdown = try XCTUnwrap(decodeFixture("claude-usage-response-ultra").usageBreakdown())

        XCTAssertEqual(breakdown.shares.map(\.name), ["Claude Code", "Chats", "Cowork", "Other"])
        XCTAssertEqual(breakdown.shares.map(\.percent), [97, 0, 3, 0])
        XCTAssertEqual(breakdown.shares.first?.key, "claude_code")
        XCTAssertNotNil(breakdown.periodStart)
        XCTAssertTrue(breakdown.hasUsage)
    }

    func testNoBreakdownWhenTheResponseHasNone() throws {
        XCTAssertNil(try decodeFixture().usageBreakdown())
    }

    private func decodeFixture(_ name: String = "claude-usage-response") throws -> ClaudeUsageResponse {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        return try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(contentsOf: url))
    }
}
