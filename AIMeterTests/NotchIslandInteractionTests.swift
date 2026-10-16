import XCTest
@testable import AIMeter

/// The island's hover, click and timer rules, driven as events. Pure.
final class NotchIslandInteractionTests: XCTestCase {
    private var island = NotchIslandInteraction()

    func testHoverDelayIsClampedAndConverted() {
        XCTAssertEqual(NotchIslandInteraction.dwell(seconds: 0.25), .milliseconds(250))
        XCTAssertEqual(NotchIslandInteraction.dwell(seconds: 0), .zero, "instant is allowed")
        XCTAssertEqual(NotchIslandInteraction.dwell(seconds: 5), .milliseconds(1000), "never past a second")
        XCTAssertEqual(NotchIslandInteraction.dwell(seconds: -1), .zero)
        XCTAssertEqual(NotchIslandInteraction.dwell(seconds: .nan), NotchIslandInteraction.dwell, "a corrupt value is the default")
        XCTAssertEqual(NotchIslandInteraction.dwell(seconds: NotchIslandInteraction.defaultDwellSeconds), NotchIslandInteraction.dwell)
    }

    func testResting_InsideOpensThePeek() {
        island.handle(.entered)
        XCTAssertEqual(island.timer, .dwell, "arm the dwell, do not open yet")
        XCTAssertEqual(island.level, .collapsed)
        island.handle(.dwellElapsed)
        XCTAssertEqual(island.level, .peek)
        XCTAssertEqual(island.timer, .none, "past the peek, only a click opens more")
    }

    func testRestingOnTheWingsNeverOpensEverything() {
        island.handle(.entered)
        island.handle(.dwellElapsed)
        island.handle(.left)
        island.handle(.entered)
        XCTAssertEqual(island.timer, .none, "back on the open wings, nothing is armed")
        XCTAssertEqual(island.level, .peek)
        island.handle(.tapped)
        XCTAssertEqual(island.level, .expanded, "a click opens everything")
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
        XCTAssertEqual(island.timer, .none, "re-entering the open wings cancels the leave")
        island.handle(.leaveElapsed)
        XCTAssertEqual(island.level, .peek, "a stale leave is ignored while inside")
    }

    func testAClickOpensItAndAClickInsideKeepsItOpen() {
        island.handle(.entered)
        island.handle(.tapped)
        XCTAssertEqual(island.level, .expanded, "from collapsed")
        island.handle(.tapped)
        XCTAssertEqual(island.level, .expanded, "a click inside never closes: its rows can be clicked")
        island.collapse()
        island.handle(.entered)
        island.handle(.dwellElapsed)
        island.handle(.tapped)
        XCTAssertEqual(island.level, .expanded, "from the peek")
        XCTAssertEqual(island.timer, .none)
    }

    func testAControlThatOpensAWindowClosesIt() {
        island.handle(.entered)
        island.handle(.tapped)
        island.handle(.closed)
        XCTAssertEqual(island.level, .collapsed)
        XCTAssertEqual(island.timer, .none)
        XCTAssertTrue(island.isInside, "the cursor has not left yet")
        island.handle(.left)
        XCTAssertEqual(island.timer, .none, "closed: nothing left to close on the way out")
        XCTAssertEqual(island.level, .collapsed)
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

    func testAnIslandAlreadyShowingItsRowOpensOnlyOnAClick() {
        island.skipsPeek = true
        island.handle(.entered)
        XCTAssertEqual(island.timer, .none, "resting on a row already in sight adds nothing")
        island.handle(.dwellElapsed)
        XCTAssertEqual(island.level, .collapsed, "a stale dwell does not open it either")

        island.handle(.tapped)
        XCTAssertEqual(island.level, .expanded)
        island.handle(.left)
        XCTAssertEqual(island.timer, .leave)
        island.handle(.leaveElapsed)
        XCTAssertEqual(island.level, .collapsed)
    }

    func testSkippingThePeekStillHonorsHoverOffAndTheReveal() {
        island.skipsPeek = true
        island.peeksOnHover = false
        island.handle(.entered)
        island.handle(.dwellElapsed)
        XCTAssertEqual(island.level, .collapsed, "with hover off only a click opens")
        island.handle(.tapped)
        XCTAssertEqual(island.level, .expanded)
        island.collapse()

        island.peeksOnHover = true
        island.reveal()
        XCTAssertEqual(island.level, .peek, "the first-run reveal is a peek on every screen")
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
