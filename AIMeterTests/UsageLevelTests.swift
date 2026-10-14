import XCTest
import SwiftUI
import UsageKit
@testable import AIMeter

/// The one color decision every bar makes (`UsageLevel`), and the
/// general switch that turns its yellow and red off.
final class UsageLevelTests: XCTestCase {
    func testLevelsTurnAboveSeventyAndEightyFiveOnTheFigureShown() {
        let cases: [(Double, UsageLevel)] = [
            (0, .normal), (70, .normal), (70.6, .normal), (71, .warning),
            (85, .warning), (85.9, .warning), (86, .danger), (100, .danger),
        ]
        for (used, level) in cases {
            XCTAssertEqual(UsageLevel(usedPct: used, severity: nil), level, "\(used)%")
        }
    }

    func testProviderFlagsRaiseTheLevel() {
        XCTAssertEqual(UsageLevel(usedPct: 10, severity: .warning), .warning)
        XCTAssertEqual(UsageLevel(usedPct: 10, severity: .critical), .danger)
        XCTAssertEqual(UsageLevel(usedPct: 10, severity: .exceeded), .danger)
        XCTAssertEqual(UsageLevel(usedPct: 90, severity: .warning), .danger, "a flag never lowers the level")
    }

    func testUsageColorsOffDrawsEveryBarAtTheNormalLevel() {
        var flagged = UsageWindow.make(.weekly, used: 95)
        flagged.severity = .exceeded
        XCTAssertEqual(flagged.level(usageColors: true), .danger)
        XCTAssertEqual(flagged.level(usageColors: false), .normal)
        XCTAssertEqual(UsageWindow.make(.session, used: 78).level(usageColors: false), .normal)
        XCTAssertEqual(flagged.tint(usageColors: false), Theme.accent)
        XCTAssertEqual(UsageWindow.tint(usedPct: 95, severity: .exceeded, usageColors: false), Theme.accent,
                       "the Live Activity's call agrees")
        XCTAssertEqual(UsageWindow.tint(usedPct: 78, severity: nil, usageColors: true), Theme.warning)
    }

    func testUsageColorsAreOnUntilTurnedOff() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        XCTAssertTrue(Preferences.load(from: scratch.defaults).usageColors, "fresh install, and every upgrade")
        let model = PreferencesModel(defaults: scratch.defaults)
        model.usageColors = false
        XCTAssertFalse(Preferences.load(from: scratch.defaults).usageColors, "written through, and loaded back")
    }
}
