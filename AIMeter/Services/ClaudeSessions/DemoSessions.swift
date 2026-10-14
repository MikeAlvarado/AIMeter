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

    func reset(now: Date = Date()) {
        set(DemoUsageData.claudeSessions(now: now), justFinished: nil)
    }

    func set(_ sessions: [ClaudeCodeSessionActivity], justFinished: ClaudeCodeSessionActivity?) {
        self.sessions = sessions
        self.justFinished = justFinished
    }
}
#endif
