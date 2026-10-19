import XCTest
import UsageKit
@testable import AIMeter

final class WidgetScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    // MARK: - The reset line

    func testARelativeResetUnderADayIsALiveCountdown() {
        let resetsAt = now.addingTimeInterval(2 * 3600 + 23 * 60)
        XCTAssertEqual(ResetLine.line(for: resetsAt, style: .relative, now: now), .countdown(now...resetsAt))
    }

    func testADayOrMoreAwayKeepsTheLabel() {
        let resetsAt = now.addingTimeInterval(2 * 86400 + 22 * 3600)
        XCTAssertEqual(
            ResetLine.line(for: resetsAt, style: .relative, now: now),
            .label(UsageFormatting.resetLabel(for: resetsAt, style: .relative, now: now))
        )
        // Exactly a day is the label too: the limit is strict.
        XCTAssertEqual(
            ResetLine.line(for: now.addingTimeInterval(ResetLine.countdownLimit), style: .relative, now: now),
            .label(UsageFormatting.resetLabel(for: now.addingTimeInterval(ResetLine.countdownLimit), style: .relative, now: now))
        )
    }

    func testTheAbsoluteStyleAndAPassedResetNeverCountDown() {
        let soon = now.addingTimeInterval(3600)
        XCTAssertEqual(
            ResetLine.line(for: soon, style: .absolute, now: now),
            .label(UsageFormatting.resetLabel(for: soon, style: .absolute, now: now))
        )
        let passed = now.addingTimeInterval(-60)
        XCTAssertEqual(
            ResetLine.line(for: passed, style: .relative, now: now),
            .label(UsageFormatting.resetLabel(for: passed, style: .relative, now: now))
        )
        // The very moment of the reset is not a range either.
        XCTAssertEqual(
            ResetLine.line(for: now, style: .relative, now: now),
            .label(UsageFormatting.resetLabel(for: now, style: .relative, now: now))
        )
    }

    // MARK: - The next reload

    func testTheNextReloadComesForwardToAMinuteAfterTheSoonestReset() {
        let interval: TimeInterval = 3 * 3600
        let session = now.addingTimeInterval(40 * 60)
        let weekly = now.addingTimeInterval(3 * 86400)
        XCTAssertEqual(
            WidgetSchedule.nextReload(after: now, interval: interval, resets: [weekly, session]),
            session.addingTimeInterval(WidgetSchedule.afterReset)
        )
    }

    func testTheCadenceStandsWhenEveryResetIsFartherOrPassed() {
        let interval: TimeInterval = 1800
        XCTAssertEqual(WidgetSchedule.nextReload(after: now, interval: interval, resets: []), now.addingTimeInterval(interval))
        XCTAssertEqual(
            WidgetSchedule.nextReload(after: now, interval: interval, resets: [now.addingTimeInterval(3600), now.addingTimeInterval(-10)]),
            now.addingTimeInterval(interval)
        )
    }

    // MARK: - Staleness

    func testASnapshotOvertakenByAResetIsStaleWhateverItsAge() {
        let fetchedAt = now.addingTimeInterval(-10 * 60)
        let reset = UsageSnapshot(
            providerID: ProviderCatalog.defaultProviderID, planName: "pro", fetchedAt: fetchedAt,
            windows: [UsageWindow(kind: .session, usedPct: 80, resetsAt: now.addingTimeInterval(-60))]
        )
        XCTAssertTrue(WidgetSchedule.isStale(reset, cadence: 1800, now: now))

        let fresh = UsageSnapshot(
            providerID: ProviderCatalog.defaultProviderID, planName: "pro", fetchedAt: fetchedAt,
            windows: [UsageWindow(kind: .session, usedPct: 80, resetsAt: now.addingTimeInterval(3600))]
        )
        XCTAssertFalse(WidgetSchedule.isStale(fresh, cadence: 1800, now: now))
        XCTAssertTrue(WidgetSchedule.isStale(fresh, cadence: 300, now: now), "older than the cadence")
        XCTAssertTrue(WidgetSchedule.isStale(nil, cadence: 1800, now: now))
    }

    /// A reset that was already past when the snapshot was fetched (an
    /// endpoint still reporting the old boundary) can't make it stale
    /// forever: only a reset the fetch didn't see counts.
    func testAResetBeforeTheFetchDoesNotCount() {
        let fetchedAt = now.addingTimeInterval(-60)
        let snapshot = UsageSnapshot(
            providerID: ProviderCatalog.defaultProviderID, planName: "pro", fetchedAt: fetchedAt,
            windows: [UsageWindow(kind: .session, usedPct: 80, resetsAt: fetchedAt.addingTimeInterval(-3600))]
        )
        XCTAssertFalse(WidgetSchedule.isStale(snapshot, cadence: 1800, now: now))
    }
}
