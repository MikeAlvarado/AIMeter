import XCTest
@testable import UsageKit

/// Peak state is a pure function of an instant plus a schedule, evaluated
/// in the schedule's own named timezone. The crux risk this guards
/// against: the device's own timezone (and DST within the schedule's
/// timezone) must never change the result for the same instant in time.
final class PeakCalculatorTests: XCTestCase {
    /// Mirrors Anthropic's documented policy: weekdays 5-11 AM PT.
    private let schedule = PeakCalculator.Schedule(
        timeZoneIdentifier: "America/Los_Angeles",
        weekdays: [2, 3, 4, 5, 6],
        startHour: 5,
        endHour: 11,
        lastVerified: Date(timeIntervalSince1970: 0)
    )

    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private func pt(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Weekday, inside/outside the window

    func testWeekdayMidWindowIsPeak() {
        // Tuesday 8 AM PT — squarely inside 5-11.
        XCTAssertTrue(PeakCalculator.isPeak(at: pt(2026, 8, 4, 8), schedule: schedule))
    }

    func testWeekdayJustBeforeWindowIsOffPeak() {
        XCTAssertFalse(PeakCalculator.isPeak(at: pt(2026, 8, 4, 4, 59), schedule: schedule))
    }

    func testWeekdayAtWindowStartIsPeak() {
        XCTAssertTrue(PeakCalculator.isPeak(at: pt(2026, 8, 4, 5, 0), schedule: schedule))
    }

    func testWeekdayAtWindowEndIsOffPeak() {
        // endHour is exclusive: 11:00:00 sharp is already off-peak.
        XCTAssertFalse(PeakCalculator.isPeak(at: pt(2026, 8, 4, 11, 0), schedule: schedule))
    }

    func testWeekdayJustBeforeWindowEndIsPeak() {
        XCTAssertTrue(PeakCalculator.isPeak(at: pt(2026, 8, 4, 10, 59), schedule: schedule))
    }

    func testWeekdayAfternoonIsOffPeak() {
        XCTAssertFalse(PeakCalculator.isPeak(at: pt(2026, 8, 4, 15), schedule: schedule))
    }

    // MARK: - Weekends always off-peak, regardless of hour

    func testSaturdayMorningIsOffPeak() {
        XCTAssertFalse(PeakCalculator.isPeak(at: pt(2026, 8, 1, 8), schedule: schedule))
    }

    func testSundayMorningIsOffPeak() {
        XCTAssertFalse(PeakCalculator.isPeak(at: pt(2026, 8, 2, 8), schedule: schedule))
    }

    // MARK: - DST transitions in the schedule's own timezone (America/Los_Angeles)

    func testMondayAfterFallBackTransitionIsPeak() {
        // DST ends 2026-11-01 (first Sunday in Nov). The following Monday
        // at 8 AM PT (now PST) must still read as peak — proving the
        // check follows local wall-clock hours through the transition,
        // not a fixed UTC offset frozen before the change.
        XCTAssertTrue(PeakCalculator.isPeak(at: pt(2026, 11, 2, 8), schedule: schedule))
    }

    func testMondayAfterSpringForwardTransitionIsPeak() {
        // DST begins 2027-03-14. The following Monday at 8 AM PT (now
        // PDT) must still read as peak.
        XCTAssertTrue(PeakCalculator.isPeak(at: pt(2027, 3, 15, 8), schedule: schedule))
    }

    // MARK: - Device timezone must have zero influence

    func testDeviceTimeZoneDoesNotAffectResult() {
        // Same instant (Tuesday 8 AM PT), read purely as an absolute Date,
        // must classify identically no matter what TimeZone.current is on
        // the device taking the reading — the schedule's own timezone is
        // the only one that matters.
        let instant = pt(2026, 8, 4, 8)
        let farAway = TimeZone(identifier: "Asia/Tokyo")!

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = farAway
        // Sanity check this instant really does land on a different
        // weekday/hour in Tokyo, so the test is actually exercising the
        // risk (Tokyo is UTC+9, ~16-17h ahead of PT).
        let tokyoComponents = localCalendar.dateComponents([.weekday, .hour], from: instant)
        XCTAssertNotEqual(tokyoComponents.hour, 8)

        XCTAssertTrue(PeakCalculator.isPeak(at: instant, schedule: schedule))
    }

    // MARK: - nextTransition

    func testNextTransitionFromInsideWindowIsWindowEnd() {
        let transition = PeakCalculator.nextTransition(after: pt(2026, 8, 4, 8), schedule: schedule)
        XCTAssertEqual(transition, pt(2026, 8, 4, 11))
    }

    func testNextTransitionFromOutsideWindowIsNextWindowStart() {
        let transition = PeakCalculator.nextTransition(after: pt(2026, 8, 4, 15), schedule: schedule)
        XCTAssertEqual(transition, pt(2026, 8, 5, 5))
    }

    func testNextTransitionFromFridayAfternoonSkipsToMonday() {
        // Friday afternoon off-peak → next transition is Monday's window
        // start, skipping the fully-off-peak weekend entirely.
        let transition = PeakCalculator.nextTransition(after: pt(2026, 8, 7, 15), schedule: schedule)
        XCTAssertEqual(transition, pt(2026, 8, 10, 5))
    }

    func testNilForDegenerateScheduleWithNoWeekdays() {
        let empty = PeakCalculator.Schedule(
            timeZoneIdentifier: "America/Los_Angeles",
            weekdays: [],
            startHour: 5,
            endHour: 11,
            lastVerified: Date(timeIntervalSince1970: 0)
        )
        XCTAssertNil(PeakCalculator.nextTransition(after: pt(2026, 8, 4, 8), schedule: empty))
    }
}
