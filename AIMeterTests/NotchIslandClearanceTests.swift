import XCTest
@testable import AIMeter

/// How far the wings beside a real notch may reach: the status items on
/// the right, the open app's menus on the left, the narrower side for
/// both. The notch is this Mac's (14", 1512 pt wide, a 32 pt bar).
final class NotchIslandClearanceTests: XCTestCase {
    private let notch = CGRect(x: 663, y: 950, width: 186, height: 32)
    private typealias Clearance = NotchIslandClearance

    func testTheStatusItemsRightOfTheNotch() {
        let windows = [
            Clearance.Window(frame: CGRect(x: 1013, y: 0, width: 30, height: 32), layer: 25),
            Clearance.Window(frame: CGRect(x: 1060, y: 0, width: 30, height: 32), layer: 25),
            Clearance.Window(frame: CGRect(x: 401, y: 0, width: 709, height: 672), layer: 27),
            Clearance.Window(frame: CGRect(x: 900, y: 300, width: 400, height: 300), layer: 0),
            Clearance.Window(frame: CGRect(x: 950, y: 0, width: 30, height: 24), layer: 25),
        ]
        XCTAssertEqual(Clearance.statusItemsMinX(windows, notch: notch, menuBarTop: 0, menuBarHeight: 32), 950, "the leftmost status item, whatever else is on screen")
        XCTAssertNil(Clearance.statusItemsMinX(windows, notch: notch, menuBarTop: 1117, menuBarHeight: 32), "another display's bar")
        XCTAssertNil(Clearance.statusItemsMinX([Clearance.Window(frame: CGRect(x: 600, y: 0, width: 30, height: 32), layer: 25)], notch: notch, menuBarTop: 0, menuBarHeight: 32), "one left of the notch is no limit on the right")
    }

    /// macOS 27: every status item is drawn by `MenuBarAgent`, and the
    /// Accessibility API reports each app's items. These are this Mac's,
    /// measured with two Claude apps, Weather, AlDente and the system's.
    func testTheStatusItemsFromAccessibility() {
        let items = [
            CGRect(x: 1091, y: 0, width: 17, height: 33),
            CGRect(x: 1346, y: 0, width: 146, height: 33),
            CGRect(x: 1195, y: 4, width: 56, height: 24),
            CGRect(x: 1115, y: 4, width: 73, height: 24),
            CGRect(x: 1002, y: 3, width: 42, height: 26),
            CGRect(x: 1042, y: 3, width: 42, height: 26),
        ]
        XCTAssertEqual(Clearance.statusItemsMinX(items: items, notch: notch, menuBarTop: 0, menuBarHeight: 32), 1002)
        XCTAssertNil(Clearance.statusItemsMinX(items: items, notch: notch, menuBarTop: 1117, menuBarHeight: 32), "another display's bar")
        XCTAssertNil(Clearance.statusItemsMinX(items: [CGRect(x: 1002, y: 0, width: 0, height: 0)], notch: notch, menuBarTop: 0, menuBarHeight: 32), "a hidden item")
        XCTAssertNil(Clearance.statusItemsMinX(items: [CGRect(x: 700, y: 3, width: 40, height: 26)], notch: notch, menuBarTop: 0, menuBarHeight: 32), "one pushed under the notch")
        // 1002 - 849 = 153 on the right, less the ear and the margin.
        XCTAssertEqual(Clearance.availableWing(notch: notch, menusMaxX: 385, statusItemsMinX: 1002, ear: 6), 141)
    }

    func testTheMenusLeftOfTheNotch() {
        let menus = [CGRect(x: 10, y: 0, width: 30, height: 32), CGRect(x: 60, y: 0, width: 80, height: 32), CGRect(x: 470, y: 0, width: 50, height: 32)]
        XCTAssertEqual(Clearance.menusMaxX(menus, notch: notch), 520)
        XCTAssertNil(Clearance.menusMaxX([], notch: notch))
        XCTAssertNil(Clearance.menusMaxX([CGRect(x: 700, y: 0, width: 0, height: 0)], notch: notch), "a hidden item counts for nothing")
    }

    func testTheNarrowerSideSetsBothWings() {
        XCTAssertNil(Clearance.availableWing(notch: notch, menusMaxX: nil, statusItemsMinX: nil, ear: 6), "nothing known: no limit")
        // 1013 - 849 = 164 on the right, less the ear and the margin.
        XCTAssertEqual(Clearance.availableWing(notch: notch, menusMaxX: nil, statusItemsMinX: 1013, ear: 6), 152)
        // 663 - 520 = 143 on the left wins over the right's 164.
        XCTAssertEqual(Clearance.availableWing(notch: notch, menusMaxX: 520, statusItemsMinX: 1013, ear: 6), 131)
        XCTAssertEqual(Clearance.availableWing(notch: notch, menusMaxX: 660, statusItemsMinX: nil, ear: 6), 0, "never below zero")
    }

    /// A screen without a notch: the room is measured from the line down
    /// its centre, which the drawn notch and the pill are centred on, so a
    /// "wing" is half their row. The 34" ultrawide (3440 pt, a 30 pt bar).
    func testAScreenWithoutANotchMeasuresFromItsCentre() {
        let ultrawide = NotchIslandGeometry.Screen(frame: CGRect(x: 0, y: 0, width: 3440, height: 1440), safeTop: 30, auxLeft: nil, auxRight: nil)
        let centre = Clearance.anchor(mode: .pill, screen: ultrawide)
        XCTAssertEqual(centre, CGRect(x: 1720, y: 1410, width: 0, height: 30))
        XCTAssertEqual(Clearance.anchor(mode: .drawn, screen: ultrawide), centre)
        XCTAssertEqual(Clearance.anchor(mode: .notch(notch), screen: ultrawide), notch, "a real notch is its own anchor")
        let items = [CGRect(x: 2900, y: 3, width: 40, height: 24), CGRect(x: 1200, y: 3, width: 40, height: 24)]
        XCTAssertEqual(Clearance.statusItemsMinX(items: items, notch: centre, menuBarTop: 0, menuBarHeight: 30), 2900, "only the items right of the centre")
        let menus = [CGRect(x: 10, y: 0, width: 30, height: 30), CGRect(x: 600, y: 0, width: 60, height: 30)]
        XCTAssertEqual(Clearance.menusMaxX(menus, notch: centre), 660)
        // 1720 - 660 = 1060 on the left, 2900 - 1720 = 1180 on the right,
        // less the closed pill's inset (4 pt on a 24 pt pill) and the margin.
        let ear = Clearance.ear(mode: .pill, barHeight: 24)
        XCTAssertEqual(ear, 4)
        XCTAssertEqual(Clearance.availableWing(notch: centre, menusMaxX: 660, statusItemsMinX: 2900, ear: ear), 1050)
        XCTAssertEqual(Clearance.ear(mode: .drawn, barHeight: 30), NotchIslandGeometry.Radii.closed.top, "a drawn notch has the real one's ears")
        let pastTheCentre = Clearance.menusMaxX([CGRect(x: 1600, y: 0, width: 200, height: 30)], notch: centre)
        XCTAssertEqual(Clearance.availableWing(notch: centre, menusMaxX: pastTheCentre, statusItemsMinX: nil, ear: ear), 0, "a menu running past the centre leaves no room")
    }
}
