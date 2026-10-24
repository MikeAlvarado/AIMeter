#if os(macOS)
import Foundation
import Observation
import UsageKit

/// The demo's Claude Code sessions (see "Demo mode" in `AIMeter/CLAUDE.md`):
/// what the notch island shows instead of this Mac's real ones while demo
/// mode is on, so its captures show the pets with nothing private in them.
/// Dealt fresh each time the demo starts, their times counted from then.
/// `DEBUG` builds let the island video harness change them while it
/// records (`IslandDirector`).
@MainActor
@Observable
final class DemoSessions {
    static let shared = DemoSessions()

    private(set) var sessions: [ClaudeCodeSessionActivity] = []
    /// The one asleep beside the notch for a few seconds after its turn.
    private(set) var justFinished: ClaudeCodeSessionActivity?
    /// What the demo's waiting sessions ask permission for, so the island's
    /// card shows a real-looking prompt and its Approve and Deny.
    private(set) var asks: [String: ClaudeCodePermissionAsk] = [:]

    func reset(now: Date = Date()) {
        set(DemoUsageData.claudeSessions(now: now), justFinished: nil)
        asks = DemoUsageData.claudeSessionAsks
    }

    func set(_ sessions: [ClaudeCodeSessionActivity], justFinished: ClaudeCodeSessionActivity?) {
        self.sessions = sessions
        self.justFinished = justFinished
    }

    // MARK: The card's buttons, on the demo

    /// Allowed: the session goes on, running what it asked for (the step
    /// it asked on, already its last).
    func approve(_ id: String) {
        asks[id] = nil
        update(id) { session, now in session.state = .working(since: session.workingSince ?? now) }
    }

    /// Denied, or stopped: the turn ends there.
    func deny(_ id: String) {
        asks[id] = nil
        finish(id)
    }

    func stop(_ id: String) {
        asks[id] = nil
        finish(id)
    }

    private func finish(_ id: String) {
        update(id) { session, now in session.state = .finished(at: now) }
        justFinished = sessions.first { $0.id == id }
    }

    private func update(_ id: String, _ change: (inout ClaudeCodeSessionActivity, Date) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions[index]
        change(&session, Date())
        session.lastActivity = Date()
        sessions[index] = session
    }
}
#endif
