import XCTest
@testable import AIMeter

final class NotificationSchedulerTests: XCTestCase {
    /// A reset is one instant, not a time of day: a trigger's components
    /// carry their zone, so a device that moved to another one by then
    /// still reads the same moment from them.
    func testTriggersArePinnedToAnInstant() throws {
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        let components = NotificationScheduler.triggerComponents(at: date)

        XCTAssertEqual(components.timeZone, Calendar.current.timeZone)
        for zone in ["Asia/Tokyo", "America/Los_Angeles", "Europe/Madrid"] {
            var elsewhere = Calendar(identifier: .gregorian)
            elsewhere.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            XCTAssertEqual(elsewhere.date(from: components), date, zone)
        }
    }

    /// Inside the lead time every fetch would schedule another warning a
    /// minute out; one already delivered for the window stands.
    func testARunOutWarningGoesOutOncePerWindow() {
        let reset = Date(timeIntervalSince1970: 1_793_000_000)
        let id = "runout.a.session"
        let delivered: [(identifier: String, resetsAt: TimeInterval?)] = [
            (id, reset.timeIntervalSince1970 + 0.4),
        ]

        XCTAssertTrue(NotificationScheduler.warnedAlready(delivered, identifier: id, resetsAt: reset))
        // The next window is a new one, and so is another account's.
        XCTAssertFalse(NotificationScheduler.warnedAlready(
            delivered, identifier: id, resetsAt: reset.addingTimeInterval(5 * 3600)
        ))
        XCTAssertFalse(NotificationScheduler.warnedAlready(delivered, identifier: "runout.b.session", resetsAt: reset))
        // A warning from before they carried their reset doesn't count.
        XCTAssertFalse(NotificationScheduler.warnedAlready([(id, nil)], identifier: id, resetsAt: reset))
    }
}

/// When the renewal reminder comes: the day the user set, the month's
/// last when it is shorter, the lead days before at 10:00, the next two
/// still ahead.
final class RenewalScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testTheNextTwoRemindersLeadTheDayYouSet() {
        let next = NotificationScheduler.nextRenewals(day: 26, leadDays: 3, after: date(2026, 11, 3), calendar: calendar)
        XCTAssertEqual(next.map(\.renewal), [date(2026, 11, 26, 0), date(2026, 12, 26, 0)])
        XCTAssertEqual(next.map(\.reminder), [date(2026, 11, 23, 10), date(2026, 12, 23, 10)])
    }

    func testADayPastTheMonthsEndIsItsLastDayAndAPastReminderSkipsAMonth() {
        // February has no 31st: its last day.
        let next = NotificationScheduler.nextRenewals(day: 31, leadDays: 1, after: date(2027, 2, 1), calendar: calendar)
        XCTAssertEqual(next.first?.renewal, date(2027, 2, 28, 0))
        // This month's reminder already went (the 4th, 10:00): next month's.
        let late = NotificationScheduler.nextRenewals(day: 5, leadDays: 1, after: date(2026, 11, 4, 11), calendar: calendar)
        XCTAssertEqual(late.first?.reminder, date(2026, 12, 4, 10))
    }
}
