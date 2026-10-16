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
