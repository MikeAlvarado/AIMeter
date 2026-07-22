import XCTest
@testable import UsageKit

/// Pace is a pure function of a single window plus `now`: where a steady
/// burn to the reset would put usage, and whether actual usage is on/ahead/
/// behind that line. No history involved.
final class PaceCalculatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Expected marker (elapsed fraction of the window)

    func testSessionHalfwayExpectsFiftyPercent() throws {
        // 5-hour session resetting in 2.5h → 2.5h elapsed → expected 50%.
        let window = UsageWindow(
            kind: .session,
            usedPct: 50,
            resetsAt: now.addingTimeInterval(2.5 * 3600)
        )
        let pace = try XCTUnwrap(PaceCalculator.pace(for: window, now: now))
        XCTAssertEqual(pace.expectedPct, 50, accuracy: 0.001)
        XCTAssertEqual(pace.status, .onPace)
    }

    func testWeeklyHalfwayExpectsFiftyPercent() throws {
        // 7-day weekly resetting in 3.5d → expected 50%.
        let window = UsageWindow(
            kind: .weekly,
            usedPct: 50,
            resetsAt: now.addingTimeInterval(3.5 * 86400)
        )
        let pace = try XCTUnwrap(PaceCalculator.pace(for: window, now: now))
        XCTAssertEqual(pace.expectedPct, 50, accuracy: 0.001)
    }

    func testModelSpecificUsesWeeklyDuration() throws {
        let window = UsageWindow(
            kind: .modelSpecific("Fable"),
            usedPct: 10,
            resetsAt: now.addingTimeInterval(3.5 * 86400)
        )
        let pace = try XCTUnwrap(PaceCalculator.pace(for: window, now: now))
        XCTAssertEqual(pace.expectedPct, 50, accuracy: 0.001)
        XCTAssertEqual(pace.status, .behind) // 10% used vs 50% expected
    }

    // MARK: - Status classification

    func testAheadWhenUsedExceedsExpectedBeyondTolerance() throws {
        // Halfway (expected 50), used 70 → 20pp over → ahead.
        let window = UsageWindow(kind: .session, usedPct: 70, resetsAt: now.addingTimeInterval(2.5 * 3600))
        let pace = try XCTUnwrap(PaceCalculator.pace(for: window, now: now))
        XCTAssertEqual(pace.status, .ahead)
    }

    func testBehindWhenUsedTrailsExpectedBeyondTolerance() throws {
        let window = UsageWindow(kind: .session, usedPct: 30, resetsAt: now.addingTimeInterval(2.5 * 3600))
        let pace = try XCTUnwrap(PaceCalculator.pace(for: window, now: now))
        XCTAssertEqual(pace.status, .behind)
    }

    func testWithinToleranceIsOnPace() throws {
        // expected 50, tolerance 5 → 54 counts as on pace, 56 does not.
        let onEdge = UsageWindow(kind: .session, usedPct: 54, resetsAt: now.addingTimeInterval(2.5 * 3600))
        XCTAssertEqual(try XCTUnwrap(PaceCalculator.pace(for: onEdge, now: now)).status, .onPace)

        let over = UsageWindow(kind: .session, usedPct: 56, resetsAt: now.addingTimeInterval(2.5 * 3600))
        XCTAssertEqual(try XCTUnwrap(PaceCalculator.pace(for: over, now: now)).status, .ahead)
    }

    // MARK: - Clamping at the edges

    func testElapsedPastResetClampsExpectedToHundred() throws {
        // resetsAt already in the past (stale snapshot) → expected 100.
        let window = UsageWindow(kind: .session, usedPct: 90, resetsAt: now.addingTimeInterval(-600))
        let pace = try XCTUnwrap(PaceCalculator.pace(for: window, now: now))
        XCTAssertEqual(pace.expectedPct, 100, accuracy: 0.001)
        XCTAssertEqual(pace.status, .behind) // 90 < 100
    }

    func testResetAtFullDurationAwayClampsExpectedToZero() throws {
        // resetsAt a full duration in the future → window hasn't started →
        // expected 0.
        let window = UsageWindow(kind: .session, usedPct: 0, resetsAt: now.addingTimeInterval(5 * 3600))
        let pace = try XCTUnwrap(PaceCalculator.pace(for: window, now: now))
        XCTAssertEqual(pace.expectedPct, 0, accuracy: 0.001)
        XCTAssertEqual(pace.status, .onPace)
    }

    // MARK: - No pace available

    func testNilWhenNoResetDate() {
        let window = UsageWindow(kind: .session, usedPct: 40, resetsAt: nil)
        XCTAssertNil(PaceCalculator.pace(for: window, now: now))
    }

    func testNilForCreditsKind() {
        // Credits is a spend cap, not a time window — no duration, no pace.
        let window = UsageWindow(kind: .credits, usedPct: 40, resetsAt: now.addingTimeInterval(3600))
        XCTAssertNil(PaceCalculator.pace(for: window, now: now))
    }
}
