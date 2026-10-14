import XCTest
@testable import UsageKit

/// Whether a Claude Code session is working, from its log's records (the
/// shapes measured on 2026-10-14 with Claude Code's desktop and CLI
/// clients) and from hook events.
final class ClaudeCodeSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let session = "6b1f-session"

    private func line(_ json: String) -> ClaudeCodeSessionRecord {
        ClaudeCodeSessionRecord.parse(Data(json.utf8))!
    }

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    private func stamp(_ seconds: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: at(seconds))
    }

    private func prompt(_ seconds: TimeInterval) -> String {
        #"{"type":"user","timestamp":"\#(stamp(seconds))","sessionId":"\#(session)","cwd":"/Users/me/Developer/aimeter","promptSource":"sdk","origin":{"kind":"human"},"message":{"role":"user","content":"a prompt that is never decoded"}}"#
    }

    private func toolUse(_ seconds: TimeInterval, agent: String? = nil) -> String {
        let agentField = agent.map { #","agentId":"\#($0)","isSidechain":true"# } ?? ""
        return #"{"type":"assistant","timestamp":"\#(stamp(seconds))","sessionId":"\#(session)"\#(agentField),"message":{"stop_reason":"tool_use","content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#
    }

    private func toolResult(_ seconds: TimeInterval) -> String {
        #"{"type":"user","timestamp":"\#(stamp(seconds))","sessionId":"\#(session)","toolUseResult":"output","message":{"content":[{"type":"tool_result","content":"output"}]}}"#
    }

    private func endTurn(_ seconds: TimeInterval) -> String {
        #"{"type":"assistant","timestamp":"\#(stamp(seconds))","sessionId":"\#(session)","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"done"}]}}"#
    }

    private func stopSummary(_ seconds: TimeInterval) -> String {
        #"{"type":"system","subtype":"stop_hook_summary","timestamp":"\#(stamp(seconds))","sessionId":"\#(session)"}"#
    }

    private func event(_ name: String, agent: String? = nil, notification: String? = nil) -> ClaudeCodeHookEvent {
        ClaudeCodeHookEvent(hookEventName: name, sessionId: session, agentId: agent, notificationType: notification)
    }

    func testOnlyTheShapeIsDecoded() {
        let record = line(toolUse(0))
        XCTAssertEqual(record.type, "assistant")
        XCTAssertEqual(record.message?.stopReason, "tool_use")
        XCTAssertEqual(record.message?.contentKinds, ["tool_use"])
        let typed = line(prompt(0))
        XCTAssertEqual(typed.message?.contentKinds, ["text"], "a typed prompt is a string: one text, never read")
        XCTAssertEqual(typed.message?.isPlainText, true)
        XCTAssertEqual(typed.timestamp, t0)
        XCTAssertFalse(typed.isInterruption)
        XCTAssertNil(ClaudeCodeSessionRecord.parse(Data(#"{"type":"user","timest"#.utf8)), "a partial line")
    }

    func testWhatEndsATurn() {
        XCTAssertTrue(line(endTurn(1)).endsTurn)
        XCTAssertTrue(line(stopSummary(2)).endsTurn)
        XCTAssertFalse(line(prompt(0)).endsTurn, "a prompt may join a turn under way")
        XCTAssertFalse(line(toolUse(3)).endsTurn)
        XCTAssertFalse(line(toolResult(4)).endsTurn)
        let agentEnd = #"{"type":"assistant","timestamp":"\#(stamp(5))","sessionId":"\#(session)","agentId":"a1","isSidechain":true,"message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}"#
        XCTAssertFalse(line(agentEnd).endsTurn, "a subagent's end isn't its parent's")
    }

    func testATurnWorksFromThePromptAndFinishesWithItsReply() {
        var tracker = ClaudeCodeSessionTracker()
        for json in [prompt(0), toolUse(5), toolResult(9)] {
            tracker.apply(line(json), fileSessionID: session, now: t0)
        }
        XCTAssertEqual(tracker.sessions[session]?.state, .working(since: t0))
        XCTAssertEqual(tracker.sessions[session]?.project, "aimeter")
        tracker.apply(line(endTurn(20)), fileSessionID: session, now: t0)
        tracker.apply(line(stopSummary(21)), fileSessionID: session, now: t0)
        XCTAssertEqual(tracker.sessions[session]?.state, .finished(at: at(20)), "the stop summary keeps the reply's time")
        tracker.apply(line(prompt(60)), fileSessionID: session, now: t0)
        XCTAssertEqual(tracker.sessions[session]?.state, .working(since: at(60)), "a new turn starts its own clock")
    }

    func testAnInterruptionEndsTheTurn() {
        // The marker as Claude Code writes it: text alone, as a list, with
        // no prompt source; one client also stamps `interruptedMessageId`.
        let marker = #"{"type":"user","timestamp":"\#(stamp(4))","sessionId":"\#(session)","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
        let stamped = #"{"type":"user","timestamp":"\#(stamp(4))","sessionId":"\#(session)","interruptedMessageId":"msg_1","message":{"role":"user","content":"[Request interrupted by user]"}}"#
        for json in [marker, stamped] {
            var tracker = ClaudeCodeSessionTracker()
            tracker.apply(line(toolUse(0)), fileSessionID: session, now: t0)
            tracker.apply(line(json), fileSessionID: session, now: t0)
            XCTAssertEqual(tracker.sessions[session]?.state, .finished(at: at(4)))
        }
        // A prompt sent as a list (an image with its text) is a prompt.
        let withImage = #"{"type":"user","timestamp":"\#(stamp(9))","sessionId":"\#(session)","promptSource":"sdk","message":{"role":"user","content":[{"type":"image"},{"type":"text","text":"x"}]}}"#
        XCTAssertFalse(line(withImage).isInterruption)
        let listedPrompt = #"{"type":"user","timestamp":"\#(stamp(9))","sessionId":"\#(session)","promptSource":"queued","message":{"role":"user","content":[{"type":"text","text":"x"}]}}"#
        XCTAssertFalse(line(listedPrompt).isInterruption, "text alone, but with a prompt's source")
    }

    func testASubagentOnlyKeepsItsParentWorking() {
        var tracker = ClaudeCodeSessionTracker()
        tracker.apply(line(toolUse(0)), fileSessionID: session, now: t0)
        let agentEnd = #"{"type":"assistant","timestamp":"\#(stamp(30))","sessionId":"\#(session)","agentId":"a1","isSidechain":true,"message":{"stop_reason":"end_turn","content":[{"type":"text","text":"x"}]}}"#
        tracker.apply(line(agentEnd), fileSessionID: session, agentID: "a1", now: t0)
        XCTAssertEqual(tracker.sessions[session]?.state, .working(since: t0))
        XCTAssertEqual(tracker.sessions[session]?.lastActivity, at(30))
        let agentInterrupted = #"{"type":"user","timestamp":"\#(stamp(31))","sessionId":"\#(session)","agentId":"a1","isSidechain":true,"message":{"content":[{"type":"text","text":"x"}]}}"#
        tracker.apply(line(agentInterrupted), fileSessionID: session, agentID: "a1", now: t0)
        XCTAssertEqual(tracker.sessions[session]?.state, .working(since: t0), "only the session's own thread ends its turn")
    }

    func testARecordReadLateNeverOverridesANewerState() {
        var tracker = ClaudeCodeSessionTracker()
        tracker.apply(line(prompt(0)), fileSessionID: session, now: t0)
        tracker.apply(line(endTurn(20)), fileSessionID: session, now: t0)
        // The subagent's file is read after its parent's: what it wrote
        // before the turn ended is old news.
        tracker.apply(line(toolUse(10, agent: "a1")), fileSessionID: session, agentID: "a1", now: t0)
        XCTAssertEqual(tracker.sessions[session]?.state, .finished(at: at(20)))
        // A background agent still writing after the turn ended is work.
        tracker.apply(line(toolUse(40, agent: "a1")), fileSessionID: session, agentID: "a1", now: t0)
        XCTAssertEqual(tracker.sessions[session]?.state, .working(since: at(40)))
    }

    func testAPermissionPromptLastsUntilItsAgentGoesOn() {
        var tracker = ClaudeCodeSessionTracker()
        tracker.apply(line(prompt(0)), fileSessionID: session, now: t0)
        tracker.apply(event("PermissionRequest"), now: at(10))
        XCTAssertEqual(tracker.sessions[session]?.state, .needsPermission(since: t0), "the turn keeps its start")
        // The log catching up with what preceded the prompt.
        tracker.apply(line(toolUse(9)), fileSessionID: session, now: t0)
        XCTAssertEqual(tracker.sessions[session]?.state, .needsPermission(since: t0))
        // Another agent at work doesn't answer this one's prompt.
        tracker.apply(line(toolUse(12, agent: "a1")), fileSessionID: session, agentID: "a1", now: t0)
        XCTAssertEqual(tracker.sessions[session]?.state, .needsPermission(since: t0))
        tracker.apply(line(toolResult(15)), fileSessionID: session, now: t0)
        XCTAssertEqual(tracker.sessions[session]?.state, .working(since: t0), "answered: the tool ran")

        tracker.apply(event("PermissionRequest", agent: "a1"), now: at(20))
        tracker.apply(line(toolResult(25)), fileSessionID: session, now: t0)
        XCTAssertEqual(tracker.sessions[session]?.state, .needsPermission(since: t0), "a subagent's prompt, still open")
        tracker.apply(line(toolUse(26, agent: "a1")), fileSessionID: session, agentID: "a1", now: t0)
        XCTAssertEqual(tracker.sessions[session]?.state, .working(since: t0))

        tracker.apply(event("PermissionRequest"), now: at(30))
        tracker.apply(event("Stop"), now: at(31))
        XCTAssertEqual(tracker.sessions[session]?.state, .finished(at: at(31)), "a turn's end closes every prompt")
        tracker.apply(line(toolResult(32)), fileSessionID: session, now: t0)
        XCTAssertEqual(tracker.sessions[session]?.state, .working(since: at(32)))
    }

    func testTitlesNameTheSessionAndAloneShowNothing() {
        var tracker = ClaudeCodeSessionTracker()
        tracker.apply(line(#"{"type":"ai-title","sessionId":"\#(session)","aiTitle":"Fix the build"}"#), fileSessionID: session, now: t0)
        XCTAssertTrue(tracker.visible(now: t0).isEmpty, "a title alone is not activity")
        tracker.apply(line(toolUse(0)), fileSessionID: session, now: t0)
        XCTAssertEqual(tracker.visible(now: t0).first?.name, "Fix the build")
        tracker.apply(line(#"{"type":"custom-title","sessionId":"\#(session)","customTitle":"Release 2.1"}"#), fileSessionID: session, now: t0)
        tracker.apply(line(#"{"type":"ai-title","sessionId":"\#(session)","aiTitle":"Something else"}"#), fileSessionID: session, now: t0)
        XCTAssertEqual(tracker.visible(now: t0).first?.name, "Release 2.1", "the user's own title wins")
    }

    func testWhatIsVisible() {
        var tracker = ClaudeCodeSessionTracker()
        tracker.apply(line(toolUse(0)), fileSessionID: session, now: t0)
        XCTAssertEqual(tracker.visible(now: at(1700)).count, 1)
        XCTAssertTrue(tracker.visible(now: at(1900)).isEmpty, "silent for 30 minutes: a crash or a closed app")
        tracker.apply(line(stopSummary(10)), fileSessionID: session, now: t0)
        XCTAssertEqual(tracker.visible(now: at(500)).count, 1, "finished, shown for 10 minutes")
        XCTAssertTrue(tracker.visible(now: at(700)).isEmpty)
        tracker.prune(now: at(90_000))
        XCTAssertTrue(tracker.sessions.isEmpty, "forgotten after a day")
    }

    func testTheOrderMovesOnlyWithATurn() {
        var tracker = ClaudeCodeSessionTracker()
        tracker.apply(ClaudeCodeHookEvent(hookEventName: "UserPromptSubmit", sessionId: "older"), now: at(0))
        tracker.apply(ClaudeCodeHookEvent(hookEventName: "UserPromptSubmit", sessionId: "newer"), now: at(5))
        tracker.apply(ClaudeCodeHookEvent(hookEventName: "UserPromptSubmit", sessionId: "done"), now: at(1))
        tracker.apply(ClaudeCodeHookEvent(hookEventName: "Stop", sessionId: "done"), now: at(8))
        XCTAssertEqual(tracker.visible(now: at(10)).map(\.id), ["newer", "older", "done"])
        // Writing more doesn't reorder; starting a turn does.
        tracker.apply(ClaudeCodeHookEvent(hookEventName: "PermissionRequest", sessionId: "older"), now: at(12))
        XCTAssertEqual(tracker.visible(now: at(12)).map(\.id), ["newer", "older", "done"])
        tracker.apply(ClaudeCodeHookEvent(hookEventName: "UserPromptSubmit", sessionId: "done"), now: at(13))
        XCTAssertEqual(tracker.visible(now: at(13)).map(\.id), ["done", "newer", "older"])
    }

    func testHookEvents() throws {
        let decoded = try JSONDecoder().decode(
            ClaudeCodeHookEvent.self,
            from: Data(#"{"session_id":"s1","transcript_path":"/x.jsonl","cwd":"/Users/me/web","hook_event_name":"PermissionRequest","agent_id":"a9","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}"#.utf8)
        )
        XCTAssertEqual(decoded, ClaudeCodeHookEvent(hookEventName: "PermissionRequest", sessionId: "s1", cwd: "/Users/me/web", agentId: "a9"))

        var tracker = ClaudeCodeSessionTracker()
        tracker.apply(ClaudeCodeHookEvent(hookEventName: "UserPromptSubmit", sessionId: "s1", cwd: "/Users/me/web"), now: t0)
        XCTAssertEqual(tracker.sessions["s1"]?.state, .working(since: t0))
        XCTAssertEqual(tracker.sessions["s1"]?.project, "web")
        tracker.apply(ClaudeCodeHookEvent(hookEventName: "Stop", sessionId: "s1"), now: at(20))
        XCTAssertEqual(tracker.sessions["s1"]?.state, .finished(at: at(20)))
        tracker.apply(ClaudeCodeHookEvent(hookEventName: "Notification", sessionId: "s1", notificationType: "idle_prompt"), now: at(80))
        XCTAssertEqual(tracker.sessions["s1"]?.state, .finished(at: at(20)), "the idle prompt after a stop is no news")
        tracker.apply(ClaudeCodeHookEvent(hookEventName: "SessionEnd", sessionId: "s1"), now: at(90))
        XCTAssertNil(tracker.sessions["s1"])
    }

    func testEqualityIsWhatIsShown() {
        var tracker = ClaudeCodeSessionTracker()
        tracker.apply(line(toolUse(0)), fileSessionID: session, now: t0)
        let before = tracker.visible(now: at(10))
        tracker.apply(line(toolResult(9)), fileSessionID: session, now: t0)
        XCTAssertEqual(tracker.visible(now: at(10)), before, "more of the same turn changes nothing shown")
    }
}
