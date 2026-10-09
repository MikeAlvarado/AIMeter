#if os(macOS)
import XCTest
@testable import AIMeter

/// The countdown clock's boundary math; the ticking itself is a one-line
/// sleep loop over it.
final class MinuteClockTests: XCTestCase {
    func testNextTickIsTheNextWholeMinuteStrictlyAfter() {
        let reference = Date(timeIntervalSinceReferenceDate: 7_200)
        XCTAssertEqual(MinuteClock.nextTick(after: reference), Date(timeIntervalSinceReferenceDate: 7_260), "on a boundary, a full minute later")
        XCTAssertEqual(MinuteClock.nextTick(after: reference.addingTimeInterval(1)), Date(timeIntervalSinceReferenceDate: 7_260))
        XCTAssertEqual(MinuteClock.nextTick(after: reference.addingTimeInterval(59.9)), Date(timeIntervalSinceReferenceDate: 7_260))
    }
}
#endif
