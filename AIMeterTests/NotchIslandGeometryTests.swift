import XCTest
@testable import AIMeter

/// The window's one frame and the sizes the slab is built from, from
/// screen rects — AppKit coordinates (origin bottom-left), measured on a
/// 14" MacBook Pro (1512×982 pt, 32 pt notch, 185 pt wide).
final class NotchIslandGeometryTests: XCTestCase {
    private let notchMac = NotchIslandGeometry.Screen(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
        auxRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
    )
    private let plainMac = NotchIslandGeometry.Screen(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        safeTop: 25,
        auxLeft: nil,
        auxRight: nil
    )

    func testNotchModeComesFromTheAuxiliaryAreas() {
        guard case .notch(let notch) = NotchIslandGeometry.mode(for: notchMac) else { return XCTFail("expected notch") }
        XCTAssertEqual(notch, CGRect(x: 663.5, y: 950, width: 185, height: 32))

        XCTAssertEqual(NotchIslandGeometry.mode(for: plainMac), .drawn)
        var zeroInset = notchMac
        zeroInset.safeTop = 0
        XCTAssertEqual(NotchIslandGeometry.mode(for: zeroInset), .drawn, "no safe area means no notch, whatever the areas say")
    }

    func testClosedSlabIsTheNotchPlusItsOverhang() {
        let mode = NotchIslandGeometry.mode(for: notchMac)
        let closed = NotchIslandGeometry.closedSize(notchMac, mode: mode)
        XCTAssertEqual(closed.width, 185 + 2 * NotchIslandGeometry.closedOverhang)
        XCTAssertEqual(closed.height, 32, "the bar's height, no lip")
        XCTAssertEqual(NotchIslandGeometry.barHeight(notchMac, mode: mode), 32)

        let drawn = NotchIslandGeometry.closedSize(plainMac, mode: .drawn)
        XCTAssertEqual(drawn.width, 0, "the drawn notch is as wide as its row")
        XCTAssertEqual(drawn.height, 25, "and as tall as the menu bar it sits on")
        XCTAssertEqual(NotchIslandGeometry.barHeight(plainMac, mode: .drawn), 25)
        var noBar = plainMac
        noBar.safeTop = 0
        XCTAssertEqual(NotchIslandGeometry.barHeight(noBar, mode: .drawn), NotchIslandGeometry.fallbackBarHeight)
    }

    func testWindowIsFixedCenteredOnTheNotchAndFlushWithTheTop() {
        let mode = NotchIslandGeometry.mode(for: notchMac)
        let frame = NotchIslandGeometry.windowFrame(notchMac, mode: mode)
        let widest = 185 + 2 * (NotchIslandGeometry.closedOverhang + NotchIslandGeometry.maxWing)
        XCTAssertEqual(frame.width, max(NotchIslandGeometry.expandedWidth, widest) + 2 * NotchIslandGeometry.shadowPadding)
        XCTAssertEqual(frame.height, 32 + NotchIslandGeometry.maxBodyHeight + NotchIslandGeometry.shadowPadding)
        XCTAssertEqual(frame.midX, 756, accuracy: 0.001, "centered on the notch")
        XCTAssertEqual(frame.maxY, 982, "flush with the top edge")
        XCTAssertEqual(NotchIslandGeometry.anchorX(notchMac, mode: mode), 756)

        var narrow = notchMac
        narrow.frame.size.width = 400
        XCTAssertEqual(NotchIslandGeometry.windowFrame(narrow, mode: mode).width, 400, "never wider than the screen")
    }

    func testDrawnNotchWindowIsFlushWithTheTopCenteredOnTheScreen() {
        let frame = NotchIslandGeometry.windowFrame(plainMac, mode: .drawn)
        XCTAssertEqual(frame.width, max(NotchIslandGeometry.expandedWidth, 2 * NotchIslandGeometry.maxWing) + 2 * NotchIslandGeometry.shadowPadding)
        XCTAssertEqual(frame.height, 25 + NotchIslandGeometry.maxBodyHeight + NotchIslandGeometry.shadowPadding)
        XCTAssertEqual(frame.midX, 960, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, 1080, "flush with the top edge, over the menu bar, like the real notch")
        XCTAssertEqual(NotchIslandGeometry.anchorX(plainMac, mode: .drawn), plainMac.frame.midX)
    }

    func testRadiiOpenRounder() {
        XCTAssertLessThan(NotchIslandGeometry.Radii.closed.top, NotchIslandGeometry.Radii.open.top)
        XCTAssertLessThan(NotchIslandGeometry.Radii.closed.bottom, NotchIslandGeometry.Radii.open.bottom)
    }

    func testTargetPrefersTheScreenWithANotch() {
        XCTAssertEqual(NotchIslandGeometry.target(screens: [plainMac, notchMac]), 1)
        XCTAssertEqual(NotchIslandGeometry.target(screens: [plainMac]), 0, "else the main screen")
        XCTAssertNil(NotchIslandGeometry.target(screens: []))
    }
}
