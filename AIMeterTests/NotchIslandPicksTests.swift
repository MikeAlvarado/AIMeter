import XCTest
import UsageKit
@testable import AIMeter

/// What the island's sneak shows when the user picks it: the session or
/// account a click or a swipe chose, a newer permission request taking
/// over, what a swipe turns through, and how a swipe counts. Pure.
final class NotchIslandPicksTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private typealias Sessions = NotchIslandModel.Sessions
    private typealias Pick = NotchIslandModel.SessionPick

    private func session(_ id: String, _ state: ClaudeCodeSessionActivity.State) -> ClaudeCodeSessionActivity {
        ClaudeCodeSessionActivity(id: id, customTitle: id.uppercased(), project: "aimeter", state: state, lastActivity: now)
    }

    private var working: ClaudeCodeSessionActivity.State { .working(since: now.addingTimeInterval(-300)) }
    private var waiting: ClaudeCodeSessionActivity.State { .needsPermission(since: now.addingTimeInterval(-300)) }

    private func island(accounts ids: [String], primaryID: String? = nil, sessions: [ClaudeCodeSessionActivity] = [], pick: Pick? = nil) -> NotchIslandModel {
        NotchIslandModel(
            accounts: ids.map { id in
                NotchIslandModel.AccountInput(
                    account: .managed(id, name: id.capitalized), snapshot: nil,
                    needsReauthentication: false, isOffline: false, lastError: nil
                )
            },
            primaryID: primaryID, displayMode: .used, resetStyle: .relative, modelSlotFallback: .auto,
            showCreditsAmount: false, usageColors: true, metrics: [.session, .weekly], glanceMetric: .session,
            layout: .bothSides, incident: nil, sessions: sessions, sessionPick: pick, now: now
        )
    }

    // MARK: Who leads

    func testWithNoPickASessionWaitingForPermissionLeads() {
        let island = Sessions(sessions: [session("a", working), session("b", waiting)], justFinished: nil, now: now)
        XCTAssertEqual(island.lead?.id, "b", "the one that needs the user")
    }

    func testAPickLeadsOverARequestFromBeforeIt() {
        let island = Sessions(
            sessions: [session("a", working), session("b", waiting), session("c", working)], justFinished: nil,
            pick: Pick(id: "c", at: now), askedAt: ["b": now.addingTimeInterval(-60)], now: now
        )
        XCTAssertEqual(island.lead?.id, "c")
        XCTAssertEqual(island.pets.map(\.id), ["c", "b", "a"], "the waiting one right after, never left in the count")
    }

    func testARequestAfterThePickTakesTheSneakAndGivesItBackOnceAnswered() {
        let pick = Pick(id: "a", at: now.addingTimeInterval(-60))
        let asking = Sessions(
            sessions: [session("a", working), session("b", waiting)], justFinished: nil,
            pick: pick, askedAt: ["b": now], now: now
        )
        XCTAssertEqual(asking.lead?.id, "b", "a newer request comes first")

        let answered = Sessions(sessions: [session("a", working), session("b", working)], justFinished: nil, pick: pick, now: now)
        XCTAssertEqual(answered.lead?.id, "a", "and the pick comes back")
    }

    func testARequestWithNoKnownTimeYieldsToThePick() {
        let island = Sessions(
            sessions: [session("a", working), session("b", waiting)], justFinished: nil,
            pick: Pick(id: "a", at: now), now: now
        )
        XCTAssertEqual(island.lead?.id, "a", "the demo's sessions carry no request times")
    }

    func testAPickThatIsNoLongerAtWorkLetsTheIslandChoose() {
        let island = Sessions(
            sessions: [session("a", working), session("b", working), session("c", .finished(at: now))], justFinished: nil,
            pick: Pick(id: "c", at: now), now: now
        )
        XCTAssertEqual(island.lead?.id, "a")
        XCTAssertEqual(island.rotation, ["a", "b"], "only the sessions at work turn")
    }

    // MARK: What a swipe turns

    func testWhileASessionWorksOnlyTheSessionsTurn() {
        let model = island(accounts: ["p", "w"], sessions: [session("a", working), session("b", working), session("c", working)])
        XCTAssertEqual(model.sessions.lead?.id, "a")
        XCTAssertEqual(model.rotation(by: 1), .session("b"))
        XCTAssertEqual(model.rotation(by: -1), .session("c"), "back from the first comes round to the last")

        let picked = island(accounts: ["p", "w"], sessions: [session("a", working), session("b", working), session("c", working)], pick: Pick(id: "c", at: now))
        XCTAssertEqual(picked.rotation(by: 1), .session("a"), "on from the last comes round to the first")
    }

    func testWithNoSessionTheAccountsTurn() {
        let model = island(accounts: ["p", "w", "x"], primaryID: "w")
        XCTAssertEqual(model.rotation(by: 1), .account("x"))
        XCTAssertEqual(model.rotation(by: -1), .account("p"))
        XCTAssertEqual(island(accounts: ["p", "w", "x"], primaryID: "x").rotation(by: 1), .account("p"))
        XCTAssertEqual(island(accounts: ["p", "w"]).rotation(by: 1), .account("w"), "with none chosen, the first is the one shown")
    }

    func testNothingTurnsWithOneOfEach() {
        XCTAssertNil(island(accounts: ["p"]).rotation(by: 1))
        XCTAssertNil(island(accounts: ["p", "w"], sessions: [session("a", working)]).rotation(by: 1), "one session at work: the accounts stay")
    }

    func testRotatedComesRoundAndStartsFromAnEnd() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(NotchIslandModel.rotated(ids, from: "c", by: 1), "a")
        XCTAssertEqual(NotchIslandModel.rotated(ids, from: "a", by: -1), "c")
        XCTAssertEqual(NotchIslandModel.rotated(ids, from: "b", by: 2), "a")
        XCTAssertEqual(NotchIslandModel.rotated(ids, from: nil, by: 1), "a")
        XCTAssertEqual(NotchIslandModel.rotated(ids, from: "gone", by: -1), "c")
        XCTAssertNil(NotchIslandModel.rotated(["a"], from: "a", by: 1))
        XCTAssertNil(NotchIslandModel.rotated(ids, from: "a", by: 0))
    }

    // MARK: How a swipe counts

    func testATwoFingerSwipeIsOneStepPerGesture() {
        var swipe = NotchIslandSwipe()
        XCTAssertNil(swipe.handle(.began, dx: -5, dy: 0, now: now))
        XCTAssertNil(swipe.handle(.changed, dx: -10, dy: 1, now: now))
        XCTAssertEqual(swipe.handle(.changed, dx: -12, dy: 0, now: now), 1, "the content moving left brings the next")
        XCTAssertNil(swipe.handle(.changed, dx: -40, dy: 0, now: now), "once per gesture")
        XCTAssertNil(swipe.handle(.momentum, dx: -80, dy: 0, now: now), "the inertia never counts")
        XCTAssertNil(swipe.handle(.ended, dx: 0, dy: 0, now: now))
        XCTAssertNil(swipe.handle(.began, dx: 10, dy: 0, now: now))
        XCTAssertEqual(swipe.handle(.changed, dx: 20, dy: 0, now: now), -1, "a new gesture the other way, the previous")
    }

    func testASwipeMostlyUpOrDownNeverTurns() {
        var swipe = NotchIslandSwipe()
        XCTAssertNil(swipe.handle(.began, dx: -10, dy: -30, now: now))
        XCTAssertNil(swipe.handle(.changed, dx: -20, dy: -40, now: now))
    }

    func testAWheelTurnedSidewaysIsAStepANotch() {
        var swipe = NotchIslandSwipe()
        XCTAssertEqual(swipe.handle(.wheel, dx: 1, dy: 0, now: now), -1)
        XCTAssertNil(swipe.handle(.wheel, dx: 1, dy: 0, now: now.addingTimeInterval(0.1)), "the same notch's other events")
        XCTAssertEqual(swipe.handle(.wheel, dx: -1, dy: 0, now: now.addingTimeInterval(0.5)), 1)
        XCTAssertNil(swipe.handle(.wheel, dx: 0, dy: 3, now: now.addingTimeInterval(1)), "a plain wheel scrolls nothing here")
    }

    func testADragCountsPastItsThresholdMostlySideways() {
        XCTAssertEqual(NotchIslandSwipe.step(forDrag: CGSize(width: -31, height: 4)), 1)
        XCTAssertEqual(NotchIslandSwipe.step(forDrag: CGSize(width: 40, height: 0)), -1)
        XCTAssertNil(NotchIslandSwipe.step(forDrag: CGSize(width: -20, height: 0)), "too short")
        XCTAssertNil(NotchIslandSwipe.step(forDrag: CGSize(width: -40, height: -50)), "more up than sideways")
    }
}
