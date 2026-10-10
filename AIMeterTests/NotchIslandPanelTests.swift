#if os(macOS)
import AppKit
import XCTest
@testable import AIMeter

/// The panel's window configuration: it has to sit above the menu bar
/// and its status items to take the cursor, and never activate the app.
@MainActor
final class NotchIslandPanelTests: XCTestCase {
    func testPanelSitsAboveTheMenuBarAndStatusItems() {
        let panel = NotchIslandPanel()
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.statusBar.rawValue, "below the bar, the bar takes the hover")
        XCTAssertLessThan(panel.level.rawValue, NSWindow.Level.popUpMenu.rawValue, "still under pop-up menus")
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.hasShadow)
    }
}
#endif
