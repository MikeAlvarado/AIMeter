import XCTest
import UsageKit
@testable import AIMeter

/// A session's turn as the island's card shows it: the newest steps and
/// how long each took, the six segments, how far along it is, and how it
/// ended; and the step the peek names while the session works.
final class SessionStepsTests: XCTestCase {
    private typealias Turn = NotchIslandModel.Sessions.Turn
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    private func turn(_ steps: [(ClaudeCodeTurn.Action, TimeInterval)], edits: Int = 0, plan: [ClaudeCodeTurn.PlanStatus]? = nil) -> ClaudeCodeTurn {
        ClaudeCodeTurn(start: t0, steps: steps.map { .init(action: $0.0, start: at($0.1)) }, edits: edits, plan: plan)
    }

    func testTheNewestThreeStepsAndTheirDurations() throws {
        let shown = try XCTUnwrap(Turn(turn([(.thinking, 0), (.reading, 4), (.editing, 10), (.running, 25)]), finishedAt: nil, now: at(30)))
        XCTAssertEqual(shown.steps.map(\.action), [.reading, .editing, .running])
        XCTAssertEqual(shown.steps.map(\.duration), [6, 15, nil], "the one under way has none yet")
        XCTAssertEqual(shown.history.map(\.action), [.thinking, .reading, .editing], "the card lists what it did; the headline, what it does")
        XCTAssertEqual(shown.progress, "4 steps")
        XCTAssertNil(shown.summary)
        XCTAssertFalse(shown.isFinished)
    }

    func testAFinishedTurnSaysHowItWent() throws {
        let done = try XCTUnwrap(Turn(turn([(.reading, 0), (.editing, 4)], edits: 6), finishedAt: at(13), now: at(20)))
        XCTAssertEqual(done.steps.last?.duration, 9)
        XCTAssertEqual(done.summary, "Done in 13s · 6 edits")
        XCTAssertEqual(done.segments, [.done, .done, .empty, .empty, .empty, .empty])
        let quiet = try XCTUnwrap(Turn(turn([(.reading, 0)]), finishedAt: at(75), now: at(80)))
        XCTAssertEqual(quiet.summary, "Done in 1m 15s", "no edits, no count")
        XCTAssertNil(Turn(nil, finishedAt: nil, now: t0))
    }

    func testSixSegmentsOverTheSteps() {
        XCTAssertEqual(Turn.segments(total: nil, current: 0, finished: false), [.now, .empty, .empty, .empty, .empty, .empty])
        XCTAssertEqual(Turn.segments(total: nil, current: 2, finished: false), [.done, .done, .now, .empty, .empty, .empty])
        XCTAssertEqual(Turn.segments(total: nil, current: 9, finished: false), [.done, .done, .done, .done, .done, .now],
                       "past six, the newest, the one under way last")
    }

    func testSixSegmentsOverAPlan() throws {
        XCTAssertEqual(Turn.segments(total: 4, current: 1, finished: false), [.done, .now, .empty, .empty, .empty, .empty])
        XCTAssertEqual(Turn.segments(total: 9, current: 4, finished: false), [.done, .done, .now, .empty, .empty, .empty],
                       "a long plan: the step under way with two before it")
        XCTAssertEqual(Turn.segments(total: 9, current: 8, finished: false), [.done, .done, .done, .done, .done, .now])
        let planned = try XCTUnwrap(Turn(turn([(.reading, 0)], plan: [.completed, .completed, .inProgress, .pending, .pending]), finishedAt: nil, now: at(5)))
        XCTAssertEqual(planned.progress, "Step 3 of 5")
        XCTAssertEqual(planned.segments, [.done, .done, .now, .empty, .empty, .empty])
    }

    func testThePeekNamesTheStepUnderWay() {
        var session = ClaudeCodeSessionActivity(id: "s", project: "aimeter", state: .working(since: t0), lastActivity: at(30))
        session.turn = turn([(.reading, 0), (.editing, 10)])
        let pet = SessionPet(index: 0)
        XCTAssertEqual(NotchIslandModel.Sessions.row(for: session, pet: pet, now: at(30)).action, "Editing")
        XCTAssertEqual(NotchIslandModel.Sessions.row(for: session, pet: pet, now: at(30)).detail, "Editing", "the row says what it does")
        XCTAssertTrue(NotchIslandModel.Sessions.row(for: session, pet: pet, now: at(200)).detail.hasPrefix("Editing · "), "and for how long")
        session.state = .needsPermission(since: t0)
        XCTAssertNil(NotchIslandModel.Sessions.row(for: session, pet: pet, now: at(30)).action, "waiting says so instead")
        session.turn = nil
        session.state = .working(since: t0)
        XCTAssertNil(NotchIslandModel.Sessions.row(for: session, pet: pet, now: at(30)).action, "no steps yet: Working for…")
    }

    /// The card stays on the session it opened on, or the one the user
    /// clicked, however the lead changes: a Stop once landed on another
    /// session whose turn had just started (2026-10-24).
    func testTheCardStaysOnItsSession() {
        let pet = SessionPet(index: 0)
        func row(_ id: String, turn: Bool = true) -> NotchIslandModel.Sessions.Row {
            var session = ClaudeCodeSessionActivity(id: id, project: id, state: .working(since: t0), lastActivity: t0)
            if turn { session.turn = self.turn([(.reading, 0)]) }
            return NotchIslandModel.Sessions.row(for: session, pet: pet, now: at(5))
        }
        let rows = [row("new"), row("old"), row("quiet", turn: false)]
        XCTAssertEqual(NotchIslandModel.Sessions.cardID(rows: rows, lead: "new", pinned: "old"), "old", "the lead moved; the card didn't")
        XCTAssertEqual(NotchIslandModel.Sessions.cardID(rows: rows, lead: "new", pinned: nil), "new")
        XCTAssertEqual(NotchIslandModel.Sessions.cardID(rows: rows, lead: "new", pinned: "gone"), "new", "its session left: the lead's")
        XCTAssertNil(NotchIslandModel.Sessions.cardID(rows: rows, lead: "quiet", pinned: nil), "no steps, no card")
    }

    func testNoStepsYetNoCount() throws {
        let started = try XCTUnwrap(Turn(ClaudeCodeTurn(start: t0), finishedAt: nil, now: at(1)))
        XCTAssertNil(started.progress, "not \"0 steps\"")
    }

    func testEveryActionHasALabelAndASymbol() {
        for action in ClaudeCodeTurn.Action.allCases {
            let step = Turn.Step(id: t0, action: action, count: 3, duration: nil)
            XCTAssertFalse(step.label.isEmpty)
            XCTAssertFalse(step.symbol.isEmpty)
            XCTAssertEqual(step.title, "\(step.label) · 3")
        }
    }
}
