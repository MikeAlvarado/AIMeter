import XCTest
@testable import AIMeter

/// When the island steps out of sight on a screen without a notch, how a
/// full-screen app is recognized from the window list (fixtures are the
/// lists measured on macOS 27 with the Dashboard in and out of full
/// screen), and when the pointer counts as on the island.
final class NotchIslandVisibilityTests: XCTestCase {
    private typealias Window = NotchIslandVisibility.Window
    private let display = CGRect(x: 0, y: 0, width: 3440, height: 1440)

    // MARK: - Full screen

    func testDesktopWindowListIsNotFullScreen() {
        // Measured: the island's panel, the menu bar, the full-size Dock
        // window at its own level, ordinary windows under the 31-pt bar.
        let desktop = [
            Window(layer: 27, bounds: CGRect(x: 1460, y: 0, width: 520, height: 510)),
            Window(layer: 24, bounds: CGRect(x: 0, y: 0, width: 3440, height: 30)),
            Window(layer: 20, bounds: CGRect(x: 0, y: 0, width: 3440, height: 1440)),
            Window(layer: 0, bounds: CGRect(x: 1650, y: 705, width: 900, height: 450)),
            Window(layer: 0, bounds: CGRect(x: 0, y: 31, width: 1720, height: 1319)),
            Window(layer: 0, bounds: CGRect(x: 1720, y: 31, width: 1720, height: 1319)),
        ]
        XCTAssertFalse(NotchIslandVisibility.isFullScreen(display: display, windows: desktop))
    }

    func testFullScreenWindowListIsFullScreen() {
        // Measured: no menu bar, no Dock, the app's window exactly the display.
        let fullScreen = [
            Window(layer: 27, bounds: CGRect(x: 1460, y: 0, width: 520, height: 510)),
            Window(layer: 0, bounds: CGRect(x: 0, y: -32, width: 3440, height: 32)),
            Window(layer: 0, bounds: CGRect(x: 0, y: 0, width: 3440, height: 1440)),
        ]
        XCTAssertTrue(NotchIslandVisibility.isFullScreen(display: display, windows: fullScreen))
    }

    func testOnlyANormalWindowOfExactlyTheDisplaysSizeCounts() {
        let zoomed = Window(layer: 0, bounds: CGRect(x: 0, y: 30, width: 3440, height: 1410))
        XCTAssertFalse(NotchIslandVisibility.isFullScreen(display: display, windows: [zoomed]), "a zoomed window leaves the menu bar")
        let dock = Window(layer: 20, bounds: display)
        XCTAssertFalse(NotchIslandVisibility.isFullScreen(display: display, windows: [dock]), "the Dock's window is full size at its own level")
        let rounding = Window(layer: 0, bounds: CGRect(x: 0.5, y: -0.5, width: 3440.5, height: 1440))
        XCTAssertTrue(NotchIslandVisibility.isFullScreen(display: display, windows: [rounding]), "within a point")
        let otherDisplay = Window(layer: 0, bounds: CGRect(x: 3440, y: 0, width: 1512, height: 982))
        XCTAssertFalse(NotchIslandVisibility.isFullScreen(display: display, windows: [otherDisplay]), "another display's full screen is not this one's")
        XCTAssertFalse(NotchIslandVisibility.isFullScreen(display: .zero, windows: [Window(layer: 0, bounds: .zero)]), "no display, no answer")
        XCTAssertFalse(NotchIslandVisibility.isFullScreen(display: display, windows: []))
    }

    func testSplitViewAndBorderlessFullScreenCount() {
        // Split View: two windows from the top edge, full height, a divider apart.
        let halves = [
            Window(layer: 0, bounds: CGRect(x: 0, y: 0, width: 1716, height: 1440)),
            Window(layer: 0, bounds: CGRect(x: 1724, y: 0, width: 1716, height: 1440)),
        ]
        XCTAssertTrue(NotchIslandVisibility.isFullScreen(display: display, windows: halves))
        XCTAssertTrue(NotchIslandVisibility.isFullScreen(display: display, windows: [halves[1]]), "either half is enough")
        // A game's borderless full screen at level 0, the display's size, no Space change.
        XCTAssertTrue(NotchIslandVisibility.isFullScreen(display: display, windows: [Window(layer: 0, bounds: display)]))
        // A narrow full-height strip (a sidebar utility) is not full screen.
        let strip = Window(layer: 0, bounds: CGRect(x: 0, y: 0, width: 300, height: 1440))
        XCTAssertFalse(NotchIslandVisibility.isFullScreen(display: display, windows: [strip]))
        // Full height but starting under the menu bar is an ordinary tall window.
        let tall = Window(layer: 0, bounds: CGRect(x: 0, y: 30, width: 3440, height: 1440))
        XCTAssertFalse(NotchIslandVisibility.isFullScreen(display: display, windows: [tall]))
    }

    func testSecondaryDisplayUsesItsOwnGlobalBounds() {
        let secondary = CGRect(x: -2560, y: -200, width: 2560, height: 1440)
        let app = Window(layer: 0, bounds: secondary)
        XCTAssertTrue(NotchIslandVisibility.isFullScreen(display: secondary, windows: [app]))
        XCTAssertFalse(NotchIslandVisibility.isFullScreen(display: display, windows: [app]))
    }

    // MARK: - Concealment

    func testConcealmentTruthTable() {
        let levels: [NotchIslandInteraction.Level] = [.collapsed, .peek, .expanded]
        let modes: [NotchIslandGeometry.Mode] = [.notch(CGRect(x: 0, y: 0, width: 185, height: 32)), .drawn, .pill]
        var concealedCases = 0
        for mode in modes {
            for level in levels {
                for revealing in [false, true] {
                    for untilHover in [false, true] {
                        for inFullScreen in [false, true] {
                            for fullScreen in [false, true] {
                                for inside in [false, true] {
                                    for peeks in [false, true] {
                                        let concealed = NotchIslandVisibility.isConcealed(
                                            mode: mode, level: level, isRevealing: revealing,
                                            hidesUntilHover: untilHover, hidesInFullScreen: inFullScreen, isFullScreen: fullScreen,
                                            pointerInside: inside, peeksOnHover: peeks
                                        )
                                        let expected = mode.drawsOwnShape && level == .collapsed && !revealing
                                            && !(inside && !peeks)
                                            && (untilHover || (inFullScreen && fullScreen))
                                        XCTAssertEqual(concealed, expected, "\(mode) \(level) revealing \(revealing) until \(untilHover) fs-option \(inFullScreen) fs \(fullScreen) inside \(inside) peeks \(peeks)")
                                        if concealed { concealedCases += 1 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // Two drawn modes × the five option combinations that hide × the
        // three pointer/peek combinations that keep it hidden.
        XCTAssertEqual(concealedCases, 2 * 5 * 3)
    }

    func testWithPeekOffTheHiddenIslandShowsWhileThePointerIsOnIt() {
        func concealed(inside: Bool, peeks: Bool) -> Bool {
            NotchIslandVisibility.isConcealed(
                mode: .pill, level: .collapsed, isRevealing: false,
                hidesUntilHover: true, hidesInFullScreen: true, isFullScreen: false,
                pointerInside: inside, peeksOnHover: peeks
            )
        }
        XCTAssertTrue(concealed(inside: false, peeks: false))
        XCTAssertFalse(concealed(inside: true, peeks: false), "no peek will ever come: show the row so it can be clicked")
        XCTAssertTrue(concealed(inside: true, peeks: true), "with peek on, it waits for the peek (the hover delay)")
    }

    func testARealNotchNeverConceals() {
        XCTAssertFalse(NotchIslandVisibility.isConcealed(
            mode: .notch(.zero), level: .collapsed, isRevealing: false,
            hidesUntilHover: true, hidesInFullScreen: true, isFullScreen: true
        ), "collapsed, the island already is the notch")
    }

    // MARK: - Pointer

    func testOnlyADrawnIslandInSightShowsItsRowWhenCollapsed() {
        let notch = NotchIslandGeometry.Mode.notch(CGRect(x: 0, y: 0, width: 200, height: 32))
        XCTAssertFalse(NotchIslandVisibility.showsRowWhenCollapsed(mode: notch, hidesUntilHover: false, hidesInFullScreen: true, isFullScreen: false), "a real notch shows nothing collapsed")
        for mode in [NotchIslandGeometry.Mode.drawn, .pill] {
            XCTAssertTrue(NotchIslandVisibility.showsRowWhenCollapsed(mode: mode, hidesUntilHover: false, hidesInFullScreen: true, isFullScreen: false))
            XCTAssertFalse(NotchIslandVisibility.showsRowWhenCollapsed(mode: mode, hidesUntilHover: true, hidesInFullScreen: false, isFullScreen: false), "hidden until hovered")
            XCTAssertFalse(NotchIslandVisibility.showsRowWhenCollapsed(mode: mode, hidesUntilHover: false, hidesInFullScreen: true, isFullScreen: true), "hidden behind a full-screen app")
            XCTAssertTrue(NotchIslandVisibility.showsRowWhenCollapsed(mode: mode, hidesUntilHover: false, hidesInFullScreen: false, isFullScreen: true), "full screen without the option keeps it")
        }
    }

    func testThePointerPushedAgainstTheTopEdgeIsInside() {
        // AppKit reports the topmost pixel row as exactly the screen's maxY.
        let region = CGRect(x: 1600, y: 1410, width: 240, height: 30)
        XCTAssertFalse(region.contains(CGPoint(x: 1720, y: 1440)), "CGRect.contains leaves maxY out — the bug this guards")
        XCTAssertTrue(NotchIslandVisibility.pointerIsInside(CGPoint(x: 1720, y: 1440), region: region, slab: .zero))
        let slab = CGRect(x: 1500, y: 1100, width: 440, height: 340)
        XCTAssertTrue(NotchIslandVisibility.pointerIsInside(CGPoint(x: 1510, y: 1440), region: region, slab: slab), "the open slab's top edge too")
        XCTAssertFalse(NotchIslandVisibility.pointerIsInside(CGPoint(x: 1720, y: 1441), region: region, slab: .zero), "nothing above the screen")
        XCTAssertFalse(NotchIslandVisibility.pointerIsInside(CGPoint(x: 1840, y: 1420), region: region, slab: .zero), "the right edge stays exclusive")
    }

    func testPointerCountsOnThePlaceOrOnWhatIsDrawn() {
        let region = CGRect(x: 1600, y: 1410, width: 240, height: 30)
        let open = CGRect(x: 1500, y: 1100, width: 440, height: 340)
        XCTAssertTrue(NotchIslandVisibility.pointerIsInside(CGPoint(x: 1720, y: 1439), region: region, slab: .zero))
        XCTAssertFalse(NotchIslandVisibility.pointerIsInside(CGPoint(x: 1720, y: 1200), region: region, slab: .zero))
        XCTAssertTrue(NotchIslandVisibility.pointerIsInside(CGPoint(x: 1720, y: 1200), region: region, slab: open), "the open island's body")
        XCTAssertFalse(NotchIslandVisibility.pointerIsInside(CGPoint(x: 100, y: 100), region: region, slab: open))
    }
}
