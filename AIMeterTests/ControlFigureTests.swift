import XCTest
import UsageKit
@testable import AIMeter

/// iOS 18's control reads like the Lock Screen gauge: the glance window,
/// its short title and the percentage as Settings displays it.
final class ControlFigureTests: XCTestCase {
    func testTheGlanceWindowAsTheGaugeReadsIt() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        var prefs = Preferences.load(from: scratch.defaults)
        let snapshot = DemoUsageData.snapshot()
        prefs.glanceMetric = .session
        prefs.displayMode = .used
        let session = snapshot.window(for: .session)!
        let used = ControlFigure(accountID: "a", name: "Personal", snapshot: snapshot, prefs: prefs)
        XCTAssertEqual(used.title, "Personal")
        XCTAssertEqual(used.figure, "\(session.shortTitle) \(Int(session.displayedPct(.used)))%")
        XCTAssertEqual(used.fraction, session.displayedPct(.used) / 100, accuracy: 0.001)

        prefs.displayMode = .remaining
        let left = ControlFigure(accountID: "a", name: "Personal", snapshot: snapshot, prefs: prefs)
        XCTAssertEqual(left.figure, "\(session.shortTitle) \(Int(session.displayedPct(.remaining)))%", "left, as Settings shows it")
    }

    func testNoSnapshotYet() {
        let figure = ControlFigure(accountID: "a", name: "Work", snapshot: nil, prefs: Preferences.load(from: ScratchDefaults().defaults))
        XCTAssertEqual(figure.figure, "--")
        XCTAssertEqual(figure.fraction, 0)
    }
}
