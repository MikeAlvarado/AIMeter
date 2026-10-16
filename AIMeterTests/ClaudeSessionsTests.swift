import XCTest
import UsageKit
@testable import AIMeter

/// Claude Code's sessions in the island: the preferences, what the mark,
/// the count and the rows say, and on the Mac the hooks' edits to Claude
/// Code's settings, the log paths and the hook requests. Pure: nothing
/// here reads a real log, opens the socket or touches ~/.claude.
final class ClaudeSessionsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ id: String, _ state: ClaudeCodeSessionActivity.State, title: String? = nil, project: String? = "aimeter") -> ClaudeCodeSessionActivity {
        ClaudeCodeSessionActivity(id: id, customTitle: title, project: project, state: state, lastActivity: now)
    }

    func testPreferences() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let fresh = Preferences.load(from: scratch.defaults)
        XCTAssertTrue(fresh.claudeSessionsEnabled, "on by default, so presence-checked")
        XCTAssertFalse(fresh.claudeSessionsNotify)
        XCTAssertFalse(fresh.claudeSessionsHooksDismissed)
        XCTAssertTrue(fresh.claudeSessionsPets, "pets on by default, presence-checked")
        XCTAssertFalse(fresh.claudeSessionsShowsName, "off by default: a short island")

        let model = PreferencesModel(defaults: scratch.defaults)
        model.claudeSessionsEnabled = false
        model.claudeSessionsNotify = true
        model.claudeSessionsHooksDismissed = true
        model.claudeSessionsPets = false
        model.claudeSessionsShowsName = true
        let reloaded = Preferences.load(from: scratch.defaults)
        XCTAssertFalse(reloaded.claudeSessionsEnabled, "a written false is honored")
        XCTAssertTrue(reloaded.claudeSessionsNotify)
        XCTAssertTrue(reloaded.claudeSessionsHooksDismissed)
        XCTAssertFalse(reloaded.claudeSessionsPets)
        XCTAssertTrue(reloaded.claudeSessionsShowsName)
    }

    /// "Avoid covering the menu bar": macOS's prompt only while the
    /// permission never worked, and a copy that lost it to another
    /// signature told how to mend it rather than asked again.
    func testAccessibilityAsksOnlyWhenItNeverWorked() {
        XCTAssertEqual(AccessibilityState(trusted: true, confirmedBefore: false), .granted)
        XCTAssertEqual(AccessibilityState(trusted: true, confirmedBefore: true), .granted)
        XCTAssertEqual(AccessibilityState(trusted: false, confirmedBefore: false), .notGranted)
        XCTAssertEqual(AccessibilityState(trusted: false, confirmedBefore: true), .lostForThisCopy)
        XCTAssertTrue(AccessibilityState.notGranted.mayPrompt)
        XCTAssertFalse(AccessibilityState.lostForThisCopy.mayPrompt, "System Settings may show it on: no prompt")
        XCTAssertFalse(AccessibilityState.granted.mayPrompt)
        #if os(macOS)
        XCTAssertNil(AccessibilityState.granted.remedy)
        XCTAssertEqual(AccessibilityState.notGranted.remedy, "Allow AIMeter in Privacy & Security, Accessibility.")
        XCTAssertTrue(AccessibilityState.lostForThisCopy.remedy?.contains("remove AIMeter") == true)
        #endif

        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        XCTAssertFalse(Preferences.load(from: scratch.defaults).claudeSessionsAccessibilityConfirmed)
        PreferencesModel(defaults: scratch.defaults).claudeSessionsAccessibilityConfirmed = true
        XCTAssertTrue(Preferences.load(from: scratch.defaults).claudeSessionsAccessibilityConfirmed)
    }

    func testTheMarkGoesByUrgency() {
        typealias Sessions = NotchIslandModel.Sessions
        XCTAssertNil(Sessions(sessions: [], justFinished: nil, now: now).mark, "nothing at work: the bare notch")
        let working = session("w", .working(since: now))
        let waiting = session("p", .needsPermission(since: now))
        let done = session("d", .finished(at: now))
        XCTAssertNil(Sessions(sessions: [done], justFinished: nil, now: now).mark, "finished a while ago is no news")
        XCTAssertEqual(Sessions(sessions: [working], justFinished: nil, now: now).mark, .working)
        XCTAssertEqual(Sessions(sessions: [working, done], justFinished: done, now: now).mark, .finished)
        XCTAssertEqual(Sessions(sessions: [working, waiting, done], justFinished: done, now: now).mark, .waiting)
        XCTAssertEqual(Sessions(sessions: [working, waiting, done], justFinished: nil, now: now).activeCount, 2)
    }

    func testRows() {
        let sessions = NotchIslandModel.Sessions(
            sessions: [
                session("a", .working(since: now.addingTimeInterval(-30)), title: "Fix the build"),
                session("b", .working(since: now.addingTimeInterval(-185))),
                session("c", .needsPermission(since: now.addingTimeInterval(-600))),
                session("d", .finished(at: now.addingTimeInterval(-20))),
                session("e", .finished(at: now.addingTimeInterval(-125))),
                session("f", .finished(at: now.addingTimeInterval(-300))),
            ],
            justFinished: nil,
            now: now
        )
        XCTAssertEqual(sessions.rows.map(\.detail), ["Working", "Working for 3m", "Needs permission", "Done just now", "Done 2m ago"])
        XCTAssertEqual(sessions.rows.map(\.status), [.working, .working, .waiting, .finished, .finished])
        XCTAssertEqual(sessions.moreCount, 1, "five rows at most")
        XCTAssertEqual(sessions.rows[0].name, "Fix the build")
        XCTAssertEqual(sessions.rows[0].project, "aimeter", "the folder after a title")
        XCTAssertEqual(sessions.rows[1].name, "aimeter")
        XCTAssertNil(sessions.rows[1].project, "a session named by its folder doesn't repeat it")
        XCTAssertEqual(sessions.rows[0].accessibilityLabel, "Fix the build, Working")
    }

    func testPets() {
        let sessions = NotchIslandModel.Sessions(
            sessions: [
                session("a", .working(since: now)),
                session("c", .working(since: now)),
                session("d", .working(since: now)),
                session("b", .needsPermission(since: now)),
                session("e", .finished(at: now)),
            ],
            justFinished: session("e", .finished(at: now)),
            now: now
        )
        XCTAssertTrue(sessions.showsPets, "on by default")
        XCTAssertEqual(sessions.pets.map(\.id), ["b", "a", "c"], "three beside the notch, the one waiting first even from fourth place")
        XCTAssertEqual(sessions.pets.map(\.pose), [.waiting, .working, .working])
        XCTAssertEqual(sessions.morePets, 2, "d at work, and e asleep")
        XCTAssertEqual(sessions.count, 5, "the count says every one")
        XCTAssertEqual(sessions.lead?.id, "b", "the lead: the one that needs you")
        XCTAssertEqual(sessions.lead?.detail, "Needs permission", "what the peek says it is doing")
        XCTAssertEqual(sessions.leftPets.map(\.id), ["b", "a"], "by default two of three on the notch's left")
        XCTAssertEqual(sessions.rightPets.map(\.id), ["c"], "and the third on its right, before the count")
        let named = NotchIslandModel.Sessions(
            sessions: [session("a", .working(since: now)), session("c", .working(since: now)), session("d", .working(since: now))],
            justFinished: nil, showsName: true, now: now
        )
        XCTAssertEqual(named.leftPets.map(\.id), ["a"], "with its name, the lead alone on the left")
        XCTAssertEqual(named.rightPets.map(\.id), ["c", "d"], "the others before the count")
        let two = NotchIslandModel.Sessions(sessions: [session("x", .working(since: now)), session("y", .working(since: now))], justFinished: nil, now: now)
        XCTAssertEqual(two.leftPets.map(\.id), ["x"], "one a side with two")
        XCTAssertEqual(two.rightPets.map(\.id), ["y"])
        for slot in sessions.pets {
            XCTAssertEqual(sessions.rows.first { $0.id == slot.id }?.pet, slot.pet, "the same pet beside the notch and in its row")
        }
        XCTAssertEqual(Set(sessions.rows.map(\.pet)).count, sessions.rows.count, "no two alike")
        XCTAssertEqual(sessions.rows.last?.pose, .asleep)

        let calm = NotchIslandModel.Sessions(sessions: [session("e", .finished(at: now))], justFinished: session("e", .finished(at: now)), now: now)
        XCTAssertEqual(calm.pets.map(\.pose), [.asleep], "the one that just finished, asleep for its few seconds")
        XCTAssertEqual(calm.count, 1)
        XCTAssertEqual(calm.leftPets.map(\.id), ["e"], "alone, on the left, the count on the right")
        XCTAssertTrue(calm.rightPets.isEmpty)
        XCTAssertTrue(NotchIslandModel.Sessions(sessions: [session("e", .finished(at: now))], justFinished: nil, now: now).pets.isEmpty)
        XCTAssertFalse(NotchIslandModel.Sessions(sessions: [], justFinished: nil, showsPets: false, now: now).showsPets)
    }

    func testTheIslandCarriesThem() {
        let island = NotchIslandModel(
            accounts: [], primaryID: nil, displayMode: .used, resetStyle: .relative, modelSlotFallback: .auto,
            showCreditsAmount: false, usageColors: true, metrics: [.session], glanceMetric: .session,
            layout: .bothSides, incident: nil, sessions: [session("a", .working(since: now))], now: now
        )
        XCTAssertEqual(island.sessions.mark, .working)
        XCTAssertEqual(island.sessions.activeCount, 1)
        XCTAssertEqual(island.sessions.markLabel, "Claude Code sessions working: 1")
    }

    #if os(macOS)
    private let theirs: [String: Any] = [
        "model": "opus",
        "hooks": [
            "Stop": [["hooks": [["type": "command", "command": "say done"]]]],
            "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "~/guard.sh"]]]],
        ],
    ]

    func testInstallingKeepsEverythingElse() throws {
        let installed = ClaudeCodeHooks.installing(into: theirs)
        XCTAssertTrue(ClaudeCodeHooks.isInstalled(in: installed))
        XCTAssertFalse(ClaudeCodeHooks.isInstalled(in: theirs))
        XCTAssertEqual(installed["model"] as? String, "opus")
        let hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 2, "their entry, then AIMeter's")
        XCTAssertEqual((stop[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String, "say done")
        XCTAssertEqual((hooks["PreToolUse"] as? [[String: Any]])?.count, 1, "an event AIMeter doesn't use is left alone")
        let permission = try XCTUnwrap((hooks["PermissionRequest"] as? [[String: Any]])?.first)
        XCTAssertEqual(permission["matcher"] as? String, "*")
        let handler = try XCTUnwrap((permission["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(handler["async"] as? Bool, true, "Claude Code never waits for it")
        XCTAssertEqual(Set(hooks.keys), Set(ClaudeCodeHooks.events).union(["PreToolUse"]))

        let again = ClaudeCodeHooks.installing(into: installed)
        XCTAssertEqual(((again["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.count, 2, "never twice")
    }

    func testRemovingTakesOutOnlyAIMetersEntries() throws {
        let removed = ClaudeCodeHooks.removing(from: ClaudeCodeHooks.installing(into: theirs))
        XCTAssertEqual(removed as NSDictionary, theirs as NSDictionary)
        let alone = ClaudeCodeHooks.removing(from: ClaudeCodeHooks.installing(into: [:]))
        XCTAssertTrue(alone.isEmpty, "an empty hooks object goes too")
    }

    func testAnOlderInstallReadsAsNotInstalled() {
        var hooks: [String: Any] = [:]
        for event in ClaudeCodeHooks.events {
            hooks[event] = [["hooks": [["type": "command", "command": "curl --unix-socket \"$HOME/Library/Application Support/AIMeter/claude-hooks.sock\" old"]]]]
        }
        let old: [String: Any] = ["hooks": hooks]
        XCTAssertFalse(ClaudeCodeHooks.isInstalled(in: old), "installing again replaces it")
        let replaced = ClaudeCodeHooks.installing(into: old)
        XCTAssertTrue(ClaudeCodeHooks.isInstalled(in: replaced))
        XCTAssertEqual(((replaced["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.count, 1)
    }

    func testWhoseLogAPathIs() {
        let root = "/Users/me/.claude/projects/-Users-me-web"
        XCTAssertTrue(ClaudeSessionLogWatcher.owner(of: "\(root)/6b1f.jsonl")! == ("6b1f", nil))
        XCTAssertTrue(ClaudeSessionLogWatcher.owner(of: "\(root)/6b1f/subagents/agent-a1.jsonl")! == ("6b1f", "a1"))
        XCTAssertTrue(ClaudeSessionLogWatcher.owner(of: "\(root)/6b1f/subagents/workflows/wf_9/agent-a2.jsonl")! == ("6b1f", "a2"))
        XCTAssertNil(ClaudeSessionLogWatcher.owner(of: "\(root)/6b1f/subagents/workflows/wf_9/journal.jsonl"))
        XCTAssertNil(ClaudeSessionLogWatcher.owner(of: "\(root)/6b1f/notes.txt"))
    }

    func testAHookRequestsBody() {
        let body = Data(#"{"hook_event_name":"Stop","session_id":"s1"}"#.utf8)
        let head = "POST /claude-hook HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(body.count)\r\n\r\n"
        let request = Data(head.utf8) + body
        XCTAssertEqual(ClaudeHookListener.body(of: request), body)
        XCTAssertNil(ClaudeHookListener.body(of: request.dropLast(3)), "not all of it yet")
        XCTAssertNil(ClaudeHookListener.body(of: Data("POST / HTTP/1.1\r\nContent-Le".utf8)))
        XCTAssertEqual(ClaudeHookListener.body(of: Data("POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n{}".utf8)), Data(),
                       "a negative length reads as none instead of trapping")
    }

    /// The demo's sessions, and the ids the website's videos use
    /// (`Scripts/IslandVideo`), deal the pets their docs and captions name.
    func testTheDemosSessionsDealThePetsTheVideosShow() {
        let sessions = DemoUsageData.claudeSessions(now: now)
        XCTAssertEqual(sessions.map(\.id), ["demo-170", "demo-54", "demo-203", "demo-70"])
        let pets = SessionPet.deal(sessions.map(\.id) + ["demo-425"])
        XCTAssertEqual(pets["demo-170"], SessionPet(creature: .fox, palette: .orange, accessory: .sunglasses))
        XCTAssertEqual(pets["demo-54"], SessionPet(creature: .cat, palette: .blue, accessory: .headphones))
        XCTAssertEqual(pets["demo-203"], SessionPet(creature: .bunny, palette: .pink, accessory: .bow))
        XCTAssertEqual(pets["demo-70"], SessionPet(creature: .ghost, palette: .purple, accessory: .beanie))
        XCTAssertEqual(pets["demo-425"], SessionPet(creature: .frog, palette: .green, accessory: .none))
        let island = NotchIslandModel.Sessions(sessions: sessions, justFinished: nil, now: now)
        XCTAssertEqual(island.pets.map(\.id), ["demo-170", "demo-54", "demo-203"], "the one waiting leads; the finished one has no pet beside the notch")
        XCTAssertEqual(island.rows.map(\.detail), ["Needs permission", "Working for 3m", "Working for 1m", "Done 2m ago"])
    }

    /// A drawn notch's or the pill's row with the session's name: the name
    /// gets what the menu bar leaves, never more than its own width, and
    /// none at all once it would be cut below 48 pt.
    func testTheDrawnRowsNameTakesWhatIsLeft() {
        // The pet, the name, the account's mark, the figures, the count.
        let ideal: [CGFloat] = [14, 200, 14, 120, 20]
        XCTAssertEqual(NamedRowLayout.widths(ideal: ideal, name: 1, spacing: 6, limit: nil), ideal, "nothing limits it: the whole name")
        // The rest is 14 + 14 + 120 + 20 and three gaps, 186; the name's own gap, 6.
        XCTAssertEqual(NamedRowLayout.widths(ideal: ideal, name: 1, spacing: 6, limit: 300)[1], 108, "cut short to the room left")
        let squeezed = NamedRowLayout.widths(ideal: ideal, name: 1, spacing: 6, limit: 230)
        XCTAssertEqual(squeezed[1], 0, "under 48 pt it is left out")
        XCTAssertEqual(NamedRowLayout.total(squeezed, spacing: 6), 186, "and the row is as short as without it")
        XCTAssertEqual(NamedRowLayout.widths(ideal: [14, 30, 14, 120, 20], name: 1, spacing: 6, limit: 230)[1], 30, "a short name shows whenever it fits whole")
        XCTAssertEqual(NamedRowLayout.widths(ideal: ideal, name: nil, spacing: 6, limit: 100), ideal, "no name, nothing to give way")
    }

    /// The "needs you" notification: a session that starts waiting for
    /// permission is announced, a turn ending never is, and the notice is
    /// taken back once the prompt is answered or the session goes away.
    func testOnlyAPermissionPromptIsAnnounced() {
        let asking = session("a", .needsPermission(since: now))
        let working = session("a", .working(since: now))
        let busy = session("b", .working(since: now))
        let done = session("b", .finished(at: now))
        XCTAssertEqual(ClaudeSessionMonitor.newlyAsking(before: ["a": working, "b": busy], after: ["a": asking, "b": done]).map(\.id), ["a"], "asking is news, finishing is not")
        XCTAssertTrue(ClaudeSessionMonitor.newlyAsking(before: ["a": asking], after: ["a": asking]).isEmpty, "still asking (another agent asked too): nothing new")
        XCTAssertEqual(ClaudeSessionMonitor.newlyAsking(before: [:], after: ["a": asking]).map(\.id), ["a"], "a session first seen asking")
        XCTAssertEqual(ClaudeSessionMonitor.noLongerAsking(before: ["a": asking], after: ["a": working]), ["a"], "answered")
        XCTAssertEqual(ClaudeSessionMonitor.noLongerAsking(before: ["a": asking], after: [:]), ["a"], "the session ended")
        XCTAssertTrue(ClaudeSessionMonitor.noLongerAsking(before: ["b": busy], after: ["b": done]).isEmpty, "it never asked")
    }
    #endif
}
