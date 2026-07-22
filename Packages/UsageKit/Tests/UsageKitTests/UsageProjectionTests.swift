import XCTest
@testable import UsageKit

/// Run-out projection has two estimators (hybrid model): a stable average
/// from a single snapshot, and a reactive recent-rate from history.
final class UsageProjectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Average projection (display)

    func testAverageOnPaceProjectsExactlyAtReset() throws {
        // Halfway through a 5h session at 50% used → average rate lands the
        // projection exactly on the reset boundary (not early).
        let window = UsageWindow(kind: .session, usedPct: 50, resetsAt: now.addingTimeInterval(2.5 * 3600))
        let p = try XCTUnwrap(RunOutPredictor.averageProjection(for: window, now: now))
        XCTAssertEqual(p.projectedExhaustion.timeIntervalSince1970, p.resetsAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertFalse(p.runsOutEarly)
    }

    func testAverageAheadRunsOutEarly() throws {
        // Halfway, but 80% used → burning fast → projected well before reset.
        let window = UsageWindow(kind: .session, usedPct: 80, resetsAt: now.addingTimeInterval(2.5 * 3600))
        let p = try XCTUnwrap(RunOutPredictor.averageProjection(for: window, now: now))
        XCTAssertTrue(p.runsOutEarly)
        XCTAssertGreaterThan(p.earlyBy, 0)
    }

    func testAverageBehindDoesNotRunOutEarly() throws {
        let window = UsageWindow(kind: .session, usedPct: 20, resetsAt: now.addingTimeInterval(2.5 * 3600))
        let p = try XCTUnwrap(RunOutPredictor.averageProjection(for: window, now: now))
        XCTAssertFalse(p.runsOutEarly)
        XCTAssertEqual(p.earlyBy, 0)
    }

    func testAverageNilWhenNotUsedOrNoResetOrNoDuration() {
        XCTAssertNil(RunOutPredictor.averageProjection(
            for: UsageWindow(kind: .session, usedPct: 0, resetsAt: now.addingTimeInterval(3600)), now: now))
        XCTAssertNil(RunOutPredictor.averageProjection(
            for: UsageWindow(kind: .session, usedPct: 40, resetsAt: nil), now: now))
        XCTAssertNil(RunOutPredictor.averageProjection(
            for: UsageWindow(kind: .credits, usedPct: 40, resetsAt: now.addingTimeInterval(3600)), now: now))
    }

    // MARK: - Recent projection (alerts)

    func testRecentRateProjectsFromSlope() throws {
        // 10pp over the last hour → 10pp/h. At 60% used, 40 left → ~4h to
        // exhaust. With the reset 5h away, that's early by ~1h.
        let samples = [
            UsageSample(timestamp: now.addingTimeInterval(-3600), usedPct: 50),
            UsageSample(timestamp: now, usedPct: 60),
        ]
        let window = UsageWindow(kind: .weekly, usedPct: 60, resetsAt: now.addingTimeInterval(5 * 3600))
        let p = try XCTUnwrap(RunOutPredictor.recentProjection(for: window, samples: samples, now: now))
        // 40pp / (10pp per 3600s) = 14400s.
        XCTAssertEqual(p.projectedExhaustion.timeIntervalSince(now), 14400, accuracy: 30)
        XCTAssertTrue(p.runsOutEarly)
        XCTAssertEqual(p.earlyBy, 3600, accuracy: 30) // 5h reset − 4h exhaust
    }

    func testRecentNilWhenFlatOrDecreasing() {
        let flat = [
            UsageSample(timestamp: now.addingTimeInterval(-3600), usedPct: 60),
            UsageSample(timestamp: now, usedPct: 60),
        ]
        let window = UsageWindow(kind: .weekly, usedPct: 60, resetsAt: now.addingTimeInterval(3600))
        XCTAssertNil(RunOutPredictor.recentProjection(for: window, samples: flat, now: now))
    }

    func testRecentNilBelowMinimumUsed() {
        let samples = [
            UsageSample(timestamp: now.addingTimeInterval(-3600), usedPct: 5),
            UsageSample(timestamp: now, usedPct: 15),
        ]
        let window = UsageWindow(kind: .weekly, usedPct: 15, resetsAt: now.addingTimeInterval(3600))
        // 15% < default 20% minimum → suppressed.
        XCTAssertNil(RunOutPredictor.recentProjection(for: window, samples: samples, now: now))
    }

    func testRecentNilWithFewerThanTwoSamples() {
        let window = UsageWindow(kind: .weekly, usedPct: 60, resetsAt: now.addingTimeInterval(3600))
        XCTAssertNil(RunOutPredictor.recentProjection(for: window, samples: [
            UsageSample(timestamp: now, usedPct: 60)
        ], now: now))
    }

    // MARK: - Early-reset detection

    func testDetectsEarlyReset() {
        let previous = UsageSnapshot(providerID: "claude", windows: [
            UsageWindow(kind: .session, usedPct: 80, resetsAt: now.addingTimeInterval(3600)),
        ])
        let current = UsageSnapshot(providerID: "claude", windows: [
            UsageWindow(kind: .session, usedPct: 5, resetsAt: now.addingTimeInterval(5 * 3600)),
        ])
        let kinds = ResetDetector.earlyResets(previous: previous, current: current, now: now)
        XCTAssertEqual(kinds, [.session])
    }

    func testNormalOnScheduleResetIsNotFlaggedEarly() {
        // The drop happens right at the previously-known reset time → normal.
        let previous = UsageSnapshot(providerID: "claude", windows: [
            UsageWindow(kind: .session, usedPct: 80, resetsAt: now),
        ])
        let current = UsageSnapshot(providerID: "claude", windows: [
            UsageWindow(kind: .session, usedPct: 5, resetsAt: now.addingTimeInterval(5 * 3600)),
        ])
        XCTAssertTrue(ResetDetector.earlyResets(previous: previous, current: current, now: now).isEmpty)
    }

    func testNoDropIsNotFlagged() {
        let previous = UsageSnapshot(providerID: "claude", windows: [
            UsageWindow(kind: .session, usedPct: 40, resetsAt: now.addingTimeInterval(3600)),
        ])
        let current = UsageSnapshot(providerID: "claude", windows: [
            UsageWindow(kind: .session, usedPct: 44, resetsAt: now.addingTimeInterval(3600)),
        ])
        XCTAssertTrue(ResetDetector.earlyResets(previous: previous, current: current, now: now).isEmpty)
    }

    // MARK: - Threshold crossing (near-limit / limit-reached)

    private func snap(_ used: Double) -> UsageSnapshot {
        UsageSnapshot(providerID: "claude", windows: [
            UsageWindow(kind: .session, usedPct: used, resetsAt: now.addingTimeInterval(3600)),
        ])
    }

    func testCrossedUpFiresOnUpwardCrossing() {
        XCTAssertEqual(
            ThresholdDetector.crossedUp(previous: snap(70), current: snap(82), threshold: 80),
            [.session]
        )
    }

    func testCrossedUpDoesNotRefireWhileAlreadyAbove() {
        // Already above the threshold in both → no crossing.
        XCTAssertTrue(
            ThresholdDetector.crossedUp(previous: snap(82), current: snap(88), threshold: 80).isEmpty
        )
    }

    func testCrossedUpIgnoresBelowThreshold() {
        XCTAssertTrue(
            ThresholdDetector.crossedUp(previous: snap(60), current: snap(75), threshold: 80).isEmpty
        )
    }

    func testLimitReachedIsCrossedUpAtLimitThreshold() {
        XCTAssertEqual(
            ThresholdDetector.crossedUp(previous: snap(94), current: snap(100),
                                        threshold: ThresholdDetector.limitReachedThreshold),
            [.session]
        )
    }

    func testNoBaselineIsNotFlagged() {
        // Window absent from previous → no crossing (avoids first-sight alert).
        let previous = UsageSnapshot(providerID: "claude", windows: [])
        XCTAssertTrue(
            ThresholdDetector.crossedUp(previous: previous, current: snap(90), threshold: 80).isEmpty
        )
    }
}
