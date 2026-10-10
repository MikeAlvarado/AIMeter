import XCTest
@testable import AIMeter

/// The island on a screen without a notch: the drawn notch and the pill,
/// the menu-bar and custom heights, the pill's gap, the row scale and the
/// hover region — first case by case on screens measured on real
/// hardware, then as invariants swept over every menu bar height and
/// custom height the settings allow.
final class NotchIslandFormGeometryTests: XCTestCase {
    /// The 34" ultrawide AIMeter was tested on (macOS 27, lid closed):
    /// 3440×1440 pt, a 30 pt menu bar, no notch.
    private let ultrawide = NotchIslandGeometry.Screen(
        frame: CGRect(x: 0, y: 0, width: 3440, height: 1440), safeTop: 30, auxLeft: nil, auxRight: nil
    )
    /// A 14" MacBook Pro: 32 pt notch, 185 pt wide.
    private let notchMac = NotchIslandGeometry.Screen(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
        auxRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
    )
    private let pill = NotchIslandGeometry.Options(form: .pill, height: nil)

    // MARK: - Mode

    func testFormOnlyMattersWithoutANotch() {
        XCTAssertEqual(NotchIslandGeometry.mode(for: ultrawide, form: .notch), .drawn)
        XCTAssertEqual(NotchIslandGeometry.mode(for: ultrawide, form: .pill), .pill)
        guard case .notch = NotchIslandGeometry.mode(for: notchMac, form: .pill) else {
            return XCTFail("a real notch is the notch, whatever the setting")
        }
        XCTAssertFalse(NotchIslandGeometry.mode(for: notchMac).drawsOwnShape)
        XCTAssertTrue(NotchIslandGeometry.Mode.drawn.drawsOwnShape)
        XCTAssertTrue(NotchIslandGeometry.Mode.pill.drawsOwnShape)
    }

    func testARealNotchIgnoresEveryOption() {
        let mode = NotchIslandGeometry.mode(for: notchMac, form: .pill)
        let custom = NotchIslandGeometry.Options(form: .pill, height: 44)
        XCTAssertEqual(NotchIslandGeometry.barHeight(notchMac, mode: mode, options: custom), 32)
        XCTAssertEqual(NotchIslandGeometry.topInset(notchMac, mode: mode, options: custom), 0)
        XCTAssertEqual(NotchIslandGeometry.rowScale(notchMac, mode: mode, options: custom), 1)
        XCTAssertEqual(
            NotchIslandGeometry.windowFrame(notchMac, mode: mode, options: custom),
            NotchIslandGeometry.windowFrame(notchMac, mode: mode),
            "the MacBook's island is exactly what it was"
        )
    }

    // MARK: - Heights

    func testDrawnNotchFollowsTheMenuBarOrTheCustomHeight() {
        XCTAssertEqual(NotchIslandGeometry.barHeight(ultrawide, mode: .drawn), 30)
        XCTAssertEqual(NotchIslandGeometry.topInset(ultrawide, mode: .drawn), 0, "fused to the top edge")
        let tall = NotchIslandGeometry.Options(form: .notch, height: 38)
        XCTAssertEqual(NotchIslandGeometry.barHeight(ultrawide, mode: .drawn, options: tall), 38)
        XCTAssertEqual(NotchIslandGeometry.topInset(ultrawide, mode: .drawn, options: tall), 0)
    }

    func testPillFloatsInsideTheMenuBar() {
        let height = NotchIslandGeometry.barHeight(ultrawide, mode: .pill, options: pill)
        let inset = NotchIslandGeometry.topInset(ultrawide, mode: .pill, options: pill)
        XCTAssertEqual(height, 30 - 2 * NotchIslandGeometry.pillInset)
        XCTAssertEqual(inset, NotchIslandGeometry.pillInset, "the same gap above and below")
        XCTAssertEqual(inset + height + inset, 30, "it fits the bar: nothing below the menu bar is covered")
    }

    func testATallPillHangsBelowTheBarKeepingItsGap() {
        let tall = NotchIslandGeometry.Options(form: .pill, height: 40)
        XCTAssertEqual(NotchIslandGeometry.barHeight(ultrawide, mode: .pill, options: tall), 40)
        XCTAssertEqual(NotchIslandGeometry.topInset(ultrawide, mode: .pill, options: tall), NotchIslandGeometry.pillMinimumInset)
        let short = NotchIslandGeometry.Options(form: .pill, height: 20)
        XCTAssertEqual(NotchIslandGeometry.topInset(ultrawide, mode: .pill, options: short), 5, "centred in the bar while it fits")
    }

    func testCustomHeightsAreClamped() {
        XCTAssertEqual(NotchIslandGeometry.barHeight(ultrawide, mode: .drawn, options: .init(form: .notch, height: 4)), 20)
        XCTAssertEqual(NotchIslandGeometry.barHeight(ultrawide, mode: .pill, options: .init(form: .pill, height: 400)), 44)
        XCTAssertEqual(NotchIslandGeometry.clampedHeight(.nan), 20, "a corrupt value is the smallest island, not a broken one")
        XCTAssertEqual(NotchIslandGeometry.clampedHeight(.infinity), 20)
    }

    func testNoReportedMenuBarFallsBackToTheStandardOne() {
        var hidden = ultrawide
        hidden.safeTop = 0
        XCTAssertEqual(NotchIslandGeometry.barHeight(hidden, mode: .drawn), NotchIslandGeometry.fallbackBarHeight)
        XCTAssertEqual(
            NotchIslandGeometry.barHeight(hidden, mode: .pill, options: pill),
            max(NotchIslandGeometry.heightRange.lowerBound - 2, NotchIslandGeometry.fallbackBarHeight - 2 * NotchIslandGeometry.pillInset)
        )
    }

    // MARK: - Shape

    func testPillIsACapsuleClosedAndACardOpen() {
        XCTAssertEqual(NotchIslandGeometry.pillRadius(barHeight: 24, expanded: false), 12, "half the height: a capsule")
        XCTAssertEqual(NotchIslandGeometry.pillRadius(barHeight: 24, expanded: true), NotchIslandGeometry.pillOpenRadius)
        XCTAssertLessThan(NotchIslandGeometry.pillOpenRadius, 60, "never a capsule around a body: that clipped 2.0.0's content")
        XCTAssertEqual(NotchIslandGeometry.pillContentInset(barHeight: 24, expanded: false), 4)
        XCTAssertEqual(NotchIslandGeometry.pillContentInset(barHeight: 12, expanded: false), 0, "never negative")
        XCTAssertEqual(NotchIslandGeometry.pillContentInset(barHeight: 24, expanded: true), NotchIslandGeometry.pillOpenInset)
    }

    func testRowScaleGrowsOnlyWithATallerIsland() {
        XCTAssertEqual(NotchIslandGeometry.rowScale(ultrawide, mode: .drawn), 1)
        XCTAssertEqual(NotchIslandGeometry.rowScale(ultrawide, mode: .pill, options: pill), 1)
        let short = NotchIslandGeometry.Options(form: .notch, height: 20)
        XCTAssertEqual(NotchIslandGeometry.rowScale(ultrawide, mode: .drawn, options: short), 1, "never shrinks below the standard row")
        let tall = NotchIslandGeometry.Options(form: .pill, height: 44)
        let scale = NotchIslandGeometry.rowScale(ultrawide, mode: .pill, options: tall)
        XCTAssertGreaterThan(scale, 1.2)
        XCTAssertLessThanOrEqual(scale, 1.35)
    }

    // MARK: - Window and hover region

    func testWindowHoldsTheGapTheBarAndTheBody() {
        let frame = NotchIslandGeometry.windowFrame(ultrawide, mode: .pill, options: pill)
        XCTAssertEqual(frame.maxY, 1440, "flush with the top edge; the gap is inside the window")
        XCTAssertEqual(frame.midX, 1720, accuracy: 0.001)
        XCTAssertEqual(frame.height, 3 + 24 + NotchIslandGeometry.maxBodyHeight + NotchIslandGeometry.shadowPadding)
    }

    func testHoverRegionStartsAtTheTopEdgeAndCoversTheRow() {
        let region = NotchIslandGeometry.hoverRegion(ultrawide, mode: .pill, options: pill, rowWidth: 200)
        XCTAssertEqual(region.maxY, 1440, "the strip above the pill is not a dead band")
        XCTAssertEqual(region.width, 200 + 2 * NotchIslandGeometry.hoverSlack)
        XCTAssertEqual(region.midX, 1720, accuracy: 0.001)
        XCTAssertTrue(region.contains(CGPoint(x: 1720, y: 1439)), "the very top pixel row")
        XCTAssertFalse(region.contains(CGPoint(x: 1720, y: 1400)), "nothing past the bar's bottom")
        let unlaid = NotchIslandGeometry.hoverRegion(ultrawide, mode: .drawn, rowWidth: 0)
        XCTAssertEqual(unlaid.width, NotchIslandGeometry.minimumHoverWidth + 2 * NotchIslandGeometry.hoverSlack, "never zero before the first layout")
    }

    // MARK: - Invariants, swept

    /// Every menu bar height a Mac reports (22–40 pt, scaled displays
    /// included) × every custom height the slider allows × both forms ×
    /// a small and a huge screen: the window stays flush with the top and
    /// inside the screen, the slab fits under it, the pill keeps a gap, a
    /// default pill never reaches past the bar, and the hover region
    /// always holds the collapsed slab.
    func testInvariantsHoldForEveryHeightAndForm() {
        let screens = [
            NotchIslandGeometry.Screen(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), safeTop: 0, auxLeft: nil, auxRight: nil),
            ultrawide,
            NotchIslandGeometry.Screen(frame: CGRect(x: -2560, y: 200, width: 2560, height: 1440), safeTop: 0, auxLeft: nil, auxRight: nil),
        ]
        var checked = 0
        for base in screens {
            for bar in stride(from: CGFloat(0), through: 40, by: 1) {
                var screen = base
                screen.safeTop = bar
                for form in NotchIslandForm.allCases {
                    let mode = NotchIslandGeometry.mode(for: screen, form: form)
                    var heights: [CGFloat?] = [nil]
                    heights += stride(from: CGFloat(18), through: 46, by: 1).map { Optional($0) }
                    for height in heights {
                        let options = NotchIslandGeometry.Options(form: form, height: height)
                        let frame = NotchIslandGeometry.windowFrame(screen, mode: mode, options: options)
                        let row = NotchIslandGeometry.barHeight(screen, mode: mode, options: options)
                        let top = NotchIslandGeometry.topInset(screen, mode: mode, options: options)
                        let scale = NotchIslandGeometry.rowScale(screen, mode: mode, options: options)
                        let context = "bar \(bar) form \(form) height \(String(describing: height)) screen \(screen.frame)"

                        XCTAssertEqual(frame.maxY, screen.frame.maxY, context)
                        XCTAssertGreaterThanOrEqual(frame.minX, screen.frame.minX - 0.001, context)
                        XCTAssertLessThanOrEqual(frame.maxX, screen.frame.maxX + 0.001, context)
                        XCTAssertEqual(frame.midX, screen.frame.midX, accuracy: 0.001, context)
                        XCTAssertGreaterThanOrEqual(frame.height, top + row + NotchIslandGeometry.maxBodyHeight, context)
                        XCTAssertGreaterThanOrEqual(row, NotchIslandGeometry.heightRange.lowerBound - 2, context)
                        XCTAssertLessThanOrEqual(row, max(NotchIslandGeometry.heightRange.upperBound, NotchIslandGeometry.menuBarHeight(screen)), context)
                        XCTAssertGreaterThanOrEqual(scale, 1, context)
                        XCTAssertLessThanOrEqual(scale, 1.35, context)
                        if mode == .pill {
                            XCTAssertGreaterThanOrEqual(top, NotchIslandGeometry.pillMinimumInset, context)
                            if height == nil, NotchIslandGeometry.menuBarHeight(screen) >= 24 {
                                XCTAssertLessThanOrEqual(top + row, NotchIslandGeometry.menuBarHeight(screen), "a default pill stays in the bar: \(context)")
                            }
                        } else {
                            XCTAssertEqual(top, 0, context)
                        }
                        let region = NotchIslandGeometry.hoverRegion(screen, mode: mode, options: options, rowWidth: 180)
                        let slab = CGRect(x: screen.frame.midX - 90, y: screen.frame.maxY - top - row, width: 180, height: row)
                        XCTAssertTrue(region.contains(slab), "the hover region holds the collapsed slab: \(context)")
                        XCTAssertEqual(region.maxY, screen.frame.maxY, context)
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked, 3 * 41 * 2 * 30)
    }
}
