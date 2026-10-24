import XCTest
@testable import UsageKit

/// A turn's steps, edits and plan, from the names of the tools its replies
/// call (shapes measured on 2026-10-23 over this Mac's logs: `tool_use`
/// items carry `caller`, `id`, `input`, `name`, `type`; the desktop app's
/// plan tool sends `items` with a `status` each, `advance`, or `done` and
/// `start`, its steps numbered from 1).
final class ClaudeCodeTurnTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let session = "6b1f-session"

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    private func stamp(_ seconds: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: at(seconds))
    }

    private func record(_ json: String) -> ClaudeCodeSessionRecord {
        ClaudeCodeSessionRecord.parse(Data(json.utf8))!
    }

    private func prompt(_ seconds: TimeInterval) -> ClaudeCodeSessionRecord {
        record(#"{"type":"user","timestamp":"\#(stamp(seconds))","sessionId":"\#(session)","promptSource":"typed","message":{"role":"user","content":"never decoded"}}"#)
    }

    private func tool(_ seconds: TimeInterval, _ name: String, id: String, input: String = #"{"command":"secret"}"#, agent: String? = nil) -> ClaudeCodeSessionRecord {
        let agentField = agent.map { #","agentId":"\#($0)","isSidechain":true"# } ?? ""
        return record(#"{"type":"assistant","timestamp":"\#(stamp(seconds))","sessionId":"\#(session)"\#(agentField),"message":{"stop_reason":"tool_use","content":[{"type":"tool_use","caller":{"type":"direct"},"id":"\#(id)","name":"\#(name)","input":\#(input)}]}}"#)
    }

    private func thinking(_ seconds: TimeInterval) -> ClaudeCodeSessionRecord {
        record(#"{"type":"assistant","timestamp":"\#(stamp(seconds))","sessionId":"\#(session)","message":{"stop_reason":"tool_use","content":[{"type":"thinking","thinking":"never decoded"}]}}"#)
    }

    private func endTurn(_ seconds: TimeInterval) -> ClaudeCodeSessionRecord {
        record(#"{"type":"assistant","timestamp":"\#(stamp(seconds))","sessionId":"\#(session)","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"done"}]}}"#)
    }

    private func run(_ records: [ClaudeCodeSessionRecord]) -> ClaudeCodeSessionActivity {
        var tracker = ClaudeCodeSessionTracker()
        for record in records {
            tracker.apply(record, fileSessionID: session, now: at(1000))
        }
        return tracker.sessions[session]!
    }

    func testOnlyTheToolsNameIsDecoded() {
        let use = tool(1, "Bash", id: "toolu_1").message?.tools
        XCTAssertEqual(use, [ClaudeCodeSessionRecord.ToolUse(id: "toolu_1", name: "Bash")])
        XCTAssertEqual(tool(1, "Bash", id: "toolu_1").message?.contentKinds, ["tool_use"])
    }

    func testConsecutiveToolsOfAKindAreOneStep() {
        let session = run([
            prompt(0),
            thinking(1),
            tool(2, "Read", id: "a"), tool(3, "Grep", id: "b"), tool(4, "Read", id: "c"), tool(5, "Read", id: "d"),
            tool(6, "Edit", id: "e"), tool(7, "Write", id: "f"),
            tool(8, "Bash", id: "g"),
            tool(9, "mcp__ccd_turn__wrap_up", id: "h"),
        ])
        let turn = session.turn!
        XCTAssertEqual(turn.start, at(0))
        XCTAssertEqual(turn.steps.map(\.action), [.thinking, .reading, .searching, .reading, .editing, .running])
        XCTAssertEqual(turn.steps.map(\.count), [1, 1, 1, 2, 2, 1])
        XCTAssertEqual(turn.steps[3].start, at(4))
        XCTAssertEqual(turn.edits, 2)
        XCTAssertEqual(turn.stepCount, 6)
        XCTAssertEqual(turn.current?.action, .running, "the desktop app's turn tools aren't a step")
    }

    func testAReplyWrittenTwiceCountsOnce() {
        let edit = tool(2, "Edit", id: "same")
        let turn = run([prompt(0), edit, edit, tool(3, "Edit", id: "other")]).turn!
        XCTAssertEqual(turn.steps.map(\.count), [2])
        XCTAssertEqual(turn.edits, 2)
    }

    func testThinkingIsAStepOnlyBeforeTheFirstTool() {
        let turn = run([prompt(0), thinking(1), tool(2, "Read", id: "a"), thinking(3), tool(4, "Read", id: "b")]).turn!
        XCTAssertEqual(turn.steps.map(\.action), [.thinking, .reading])
    }

    func testASubagentsToolsAreItsParentsDelegatingStep() {
        let turn = run([
            prompt(0),
            tool(1, "Agent", id: "a"),
            tool(2, "Read", id: "b", agent: "sub"), tool(3, "Edit", id: "c", agent: "sub"),
        ]).turn!
        XCTAssertEqual(turn.steps.map(\.action), [.delegating])
        XCTAssertEqual(turn.edits, 0)
    }

    func testANewTurnStartsAfresh() {
        let session = run([
            prompt(0), tool(1, "Edit", id: "a"), endTurn(5),
            prompt(10), tool(11, "Read", id: "b"),
        ])
        XCTAssertEqual(session.turn?.start, at(10))
        XCTAssertEqual(session.turn?.steps.map(\.action), [.reading])
        XCTAssertEqual(session.turn?.edits, 0)
    }

    func testAFinishedTurnKeepsItsSteps() {
        let session = run([prompt(0), tool(1, "Edit", id: "a"), tool(2, "Edit", id: "b"), endTurn(13)])
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.turn?.edits, 2)
        XCTAssertEqual(session.turn?.start, at(0))
    }

    func testOnlyTheNewestStepsAreKept() {
        var records = [prompt(0)]
        for index in 0..<30 {
            records.append(tool(Double(index + 1), index.isMultiple(of: 2) ? "Read" : "Bash", id: "t\(index)"))
        }
        let turn = run(records).turn!
        XCTAssertEqual(turn.steps.count, ClaudeCodeTurn.keptSteps)
        XCTAssertEqual(turn.stepCount, 30)
        XCTAssertEqual(turn.current?.start, at(30))
    }

    func testToolsMapToTheirActions() {
        XCTAssertEqual(ClaudeCodeTurn.Action(tool: "WebFetch"), .web)
        XCTAssertEqual(ClaudeCodeTurn.Action(tool: "mcp__Claude_Browser__navigate"), .browsing)
        XCTAssertEqual(ClaudeCodeTurn.Action(tool: "mcp__claude-in-chrome__computer"), .browsing)
        XCTAssertEqual(ClaudeCodeTurn.Action(tool: "mcp__notion__fetch"), .tool)
        XCTAssertEqual(ClaudeCodeTurn.Action(tool: "Glob"), .searching)
        XCTAssertEqual(ClaudeCodeTurn.Action(tool: "Task"), .delegating)
        XCTAssertNil(ClaudeCodeTurn.Action(tool: ClaudeCodeTurn.planTool))
    }

    // MARK: The plan

    private func plan(_ seconds: TimeInterval, id: String, _ input: String) -> ClaudeCodeSessionRecord {
        tool(seconds, ClaudeCodeTurn.planTool, id: id, input: input)
    }

    func testThePlansStatusesAreReadAndNotItsText() {
        let input = #"{"items":[{"content":"secret step","status":"in_progress"},{"content":"another","status":"pending"},{"content":"x","status":"pending"}],"scope":"first_task"}"#
        let use = plan(1, id: "p", input).message?.tools.first
        XCTAssertEqual(use?.plan, .set([.inProgress, .pending, .pending]))
    }

    func testThePlanAdvancesAndMarks() {
        let set = #"{"items":[{"content":"a","status":"in_progress"},{"content":"b","status":"pending"},{"content":"c","status":"pending"},{"content":"d","status":"pending"},{"content":"e","status":"pending"},{"content":"f","status":"pending"},{"content":"g","status":"pending"}],"scope":"continuation"}"#
        var records = [prompt(0), plan(1, id: "p1", set)]
        XCTAssertEqual(run(records).turn?.planPosition?.step, 1)
        XCTAssertEqual(run(records).turn?.planPosition?.of, 7)
        records += [plan(2, id: "p2", #"{"advance":true}"#), plan(3, id: "p3", #"{"advance":true}"#)]
        XCTAssertEqual(run(records).turn?.planPosition?.step, 3)
        records.append(plan(4, id: "p4", #"{"done":[3,4],"start":5}"#))
        XCTAssertEqual(run(records).turn?.planPosition?.step, 5)
        XCTAssertEqual(run(records).turn?.plan, [.completed, .completed, .completed, .completed, .inProgress, .pending, .pending])
        records.append(plan(5, id: "p5", #"{"done":[5,6],"start":7}"#))
        records.append(plan(6, id: "p6", #"{"advance":true}"#))
        XCTAssertEqual(run(records).turn?.planPosition?.step, 7, "past the last, on the last")
        XCTAssertEqual(run(records).turn?.plan?.allSatisfy { $0 == .completed }, true)
        XCTAssertEqual(run(records).turn?.steps, [], "the plan is not a step")
    }

    func testNoPlanNoPosition() {
        XCTAssertNil(run([prompt(0), tool(1, "Read", id: "a")]).turn?.planPosition)
        XCTAssertNil(run([prompt(0), plan(1, id: "p", #"{"advance":true}"#)]).turn?.plan, "advancing no plan is nothing")
    }

    // MARK: Permission asks

    func testAPermissionAskSaysWhatTheToolWouldDo() throws {
        let json = #"{"session_id":"s1","transcript_path":"/x","cwd":"/y","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"git push\norigin main","description":"Push"},"permission_suggestions":[]}"#
        let ask = try JSONDecoder().decode(ClaudeCodePermissionAsk.self, from: Data(json.utf8))
        XCTAssertEqual(ask, ClaudeCodePermissionAsk(sessionId: "s1", toolName: "Bash", subject: "git push origin main"))
        XCTAssertEqual(ask.event.hookEventName, "PermissionRequest")
    }

    func testAPermissionAskForAFileOrNothing() throws {
        let edit = #"{"session_id":"s1","agent_id":"a1","tool_name":"Edit","tool_input":{"file_path":"/repo/a.swift","old_string":"never","new_string":"decoded"}}"#
        let ask = try JSONDecoder().decode(ClaudeCodePermissionAsk.self, from: Data(edit.utf8))
        XCTAssertEqual(ask.subject, "/repo/a.swift")
        XCTAssertEqual(ask.agentId, "a1")
        let other = #"{"session_id":"s1","tool_name":"mcp__x__y","tool_input":{"anything":"else"}}"#
        XCTAssertNil(try JSONDecoder().decode(ClaudeCodePermissionAsk.self, from: Data(other.utf8)).subject)
        let long = String(repeating: "a", count: 400)
        let big = #"{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"\#(long)"}}"#
        XCTAssertEqual(try JSONDecoder().decode(ClaudeCodePermissionAsk.self, from: Data(big.utf8)).subject?.count, ClaudeCodePermissionAsk.maxSubject + 1)
    }
}
