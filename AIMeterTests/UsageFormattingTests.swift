import XCTest
import UsageKit
@testable import AIMeter

final class UsageFormattingTests: XCTestCase {
    private let now = Date()

    private func relative(_ seconds: TimeInterval) -> String {
        UsageFormatting.relativeString(from: now, to: now.addingTimeInterval(seconds))
    }

    func testTwoUnitCountdown() {
        XCTAssertEqual(relative(2 * 86400 + 3 * 3600 + 5 * 60), String(localized: "\(2)d \(3)h"))
        XCTAssertEqual(relative(4 * 3600 + 12 * 60), String(localized: "\(4)h \(12)m"))
        XCTAssertEqual(relative(38 * 60), String(localized: "\(38)m"))
    }

    func testExactUnitsDropTheRemainder() {
        XCTAssertEqual(relative(2 * 86400), String(localized: "\(2)d"))
        XCTAssertEqual(relative(3 * 3600), String(localized: "\(3)h"))
    }

    func testPastOrImminentReadsNow() {
        XCTAssertEqual(relative(0), String(localized: "now"))
        XCTAssertEqual(relative(-600), String(localized: "now"))
        XCTAssertEqual(relative(30), String(localized: "now"))
    }

    func testRelativeResetLabelWrapsTheCountdown() {
        let label = UsageFormatting.resetLabel(for: now.addingTimeInterval(3600), style: .relative, now: now)
        XCTAssertTrue(label.contains(String(localized: "\(1)h")), label)
    }

    /// The absolute style names the weekday within the week and the date
    /// from a week on, where "Mon" alone no longer says which Monday.
    func testAbsoluteResetAWeekOrMoreAwayShowsTheDate() {
        // 2026-10-19 12:00 UTC, a Monday; noon, so the day is the same in
        // every time zone the tests run in.
        let monday = Date(timeIntervalSince1970: 1_792_411_200)
        let day: TimeInterval = 24 * 3600
        let thisWeek = UsageFormatting.resetLabel(for: monday.addingTimeInterval(6 * day), style: .absolute, now: monday)
        XCTAssertFalse(thisWeek.contains("25"), "the weekday, not the 25th: \(thisWeek)")
        let nextWeek = UsageFormatting.resetLabel(for: monday.addingTimeInterval(7 * day), style: .absolute, now: monday)
        XCTAssertTrue(nextWeek.contains("26"), "the 26th, not a weekday: \(nextWeek)")
        let farOff = UsageFormatting.resetLabel(for: monday.addingTimeInterval(30 * day), style: .absolute, now: monday)
        XCTAssertTrue(farOff.contains("18"), "November 18th: \(farOff)")
        XCTAssertEqual(UsageFormatting.dateInsteadOfWeekdayFrom, 7 * day)
    }

    func testUpdatedLabelJustNow() {
        XCTAssertEqual(UsageFormatting.updatedLabel(now, now: now), String(localized: "Updated just now"))
    }

    func testGlanceOptionsFollowWhatTheAccountReports() {
        let bare = UsageSnapshot.make(windows: [.make(.session, used: 1), .make(.weekly, used: 1)])
        XCTAssertEqual(UsageSnapshot.glanceOptions(for: bare, modelSlotFallback: .auto), [.session, .weekly])

        let withModel = UsageSnapshot.make(windows: [.make(.session, used: 1), .make(.weekly, used: 1), .make(.modelSpecific("Fable"), used: 1)])
        XCTAssertEqual(UsageSnapshot.glanceOptions(for: withModel, modelSlotFallback: .auto), [.session, .weekly, .modelSpecific("Fable")])

        let withCredits = UsageSnapshot.make(
            windows: [.make(.session, used: 1), .make(.weekly, used: 1)],
            spend: SpendStatus(enabled: true, percent: 10)
        )
        XCTAssertTrue(UsageSnapshot.glanceOptions(for: withCredits, modelSlotFallback: .auto).contains(.credits))
        XCTAssertFalse(UsageSnapshot.glanceOptions(for: withCredits, modelSlotFallback: .hidden).contains(.credits))
    }

    func testDisplayModeSuffixIsOneLowercaseWord() {
        // The medium widget sets it after a big figure: "42% left".
        XCTAssertEqual(DisplayMode.remaining.suffix, "left")
        XCTAssertEqual(DisplayMode.used.suffix, "used")
    }
}
