import XCTest
@testable import AIMeter

/// The island's hover, click and timer rules, driven as events. Pure.
final class NotchIslandInteractionTests: XCTestCase {
    private var island = NotchIslandInteraction()

    func testResting_InsideOpensThePeek() {
        island.handle(.entered)
        XCTAssertEqual(island.timer, .dwell, "arm the dwell, do not open yet")
        XCTAssertEqual(island.level, .collapsed)
        island.handle(.dwellElapsed)
        XCTAssertEqual(island.level, .peek)
        XCTAssertEqual(island.timer, .expand, "staying on the wings is the next step")
    }

    func testStayingOnTheWingsOpensEverything() {
        island.handle(.entered)
        island.handle(.dwellElapsed)
        island.handle(.expandElapsed)
        XCTAssertEqual(island.level, .expanded)
        XCTAssertEqual(island.timer, .none)

        island.handle(.left)
        island.handle(.leaveElapsed)
        island.handle(.entered)
        island.handle(.dwellElapsed)
        island.handle(.left)
        island.handle(.expandElapsed)
        XCTAssertEqual(island.level, .peek, "a stale expand after leaving is ignored")
    }

    func testPassingOverDoesNotOpen() {
        island.handle(.entered)
        XCTAssertEqual(island.timer, .dwell)
        island.handle(.left)
        XCTAssertEqual(island.timer, .none, "passing over the notch never opens")
        island.handle(.dwellElapsed)
        XCTAssertEqual(island.level, .collapsed, "a stale dwell after leaving is ignored")
    }

    func testLeavingClosesAfterTheDelayWhateverOpenedIt() {
        island.handle(.entered)
        island.handle(.dwellElapsed)
        island.handle(.left)
        XCTAssertEqual(island.timer, .leave)
        XCTAssertEqual(island.level, .peek, "still open until the delay")
        island.handle(.leaveElapsed)
        XCTAssertEqual(island.level, .collapsed)

        island.handle(.entered)
        island.handle(.tapped)
        XCTAssertEqual(island.level, .expanded)
        island.handle(.left)
        island.handle(.leaveElapsed)
        XCTAssertEqual(island.level, .collapsed, "a click does not pin")
    }

    func testComingBackCancelsTheLeave() {
        island.handle(.entered)
        island.handle(.dwellElapsed)
        island.handle(.left)
        island.handle(.entered)
        XCTAssertEqual(island.timer, .expand, "re-entering the open wings arms the expand, not the leave")
        island.handle(.leaveElapsed)
        XCTAssertEqual(island.level, .peek, "a stale leave is ignored while inside")
    }

    func testClickTogglesTheFullIsland() {
        island.handle(.entered)
        island.handle(.tapped)
        XCTAssertEqual(island.level, .expanded, "from collapsed")
        island.handle(.tapped)
        XCTAssertEqual(island.level, .collapsed, "a second click closes")
        island.handle(.entered)
        island.handle(.dwellElapsed)
        island.handle(.tapped)
        XCTAssertEqual(island.level, .expanded, "from the peek")
        XCTAssertEqual(island.timer, .none, "a click cancels the expand dwell")
    }

    func testClickOutsideCloses() {
        island.handle(.entered)
        island.handle(.tapped)
        island.handle(.clickedOutside)
        XCTAssertEqual(island.level, .collapsed)
        XCTAssertFalse(island.isInside)
        XCTAssertEqual(island.timer, .none)
    }

    func testHoverOffLeavesOnlyTheClick() {
        island.peeksOnHover = false
        island.handle(.entered)
        XCTAssertEqual(island.timer, .none)
        island.handle(.dwellElapsed)
        XCTAssertEqual(island.level, .collapsed)
        island.handle(.tapped)
        XCTAssertEqual(island.level, .expanded)
    }

    func testRevealOpensThePeekAndObeysTheUsualClose() {
        island.reveal()
        XCTAssertEqual(island.level, .peek)
        XCTAssertEqual(island.timer, .none, "the reveal never expands by itself")
        island.handle(.entered)
        island.handle(.tapped)
        XCTAssertEqual(island.level, .expanded, "a click during the reveal opens everything")
        island.collapse()
        XCTAssertEqual(island.level, .collapsed)
        island.handle(.entered)
        island.reveal()
        island.handle(.left)
        island.handle(.leaveElapsed)
        XCTAssertEqual(island.level, .collapsed)
    }
}
