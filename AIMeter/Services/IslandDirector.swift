#if os(macOS) && DEBUG
import AppKit
import UsageKit

/// `DEBUG` only: lets `Scripts/IslandVideo` drive the notch island while it
/// records the website's videos (see `Scripts/IslandVideo/CLAUDE.md`).
/// Launched with `-AIMeterIslandDirector YES`, the app takes commands as
/// distributed notifications (`notification`, a `command` and a `value`
/// in `userInfo`): `demo` turns demo mode on, `level` opens the island to
/// `collapsed`, `peek` or `expanded`, `sessions` replaces the demo's
/// sessions with a JSON list (each with its turn's steps, plan and
/// permission prompt, for the card), and `approve` answers a demo
/// session's prompt as the card's Approve does. A recording needs no
/// cursor and shows no real session.
enum IslandDirector {
    static let notification = Notification.Name("com.mikealvarado.aimeter.director")

    /// One session as the harness describes it: `state` is `working`,
    /// `waiting` or `finished`, `ago` how many seconds ago its turn started
    /// (or ended, finished).
    private struct Session: Decodable {
        let id: String
        let title: String?
        let project: String?
        let state: String
        let ago: Double
        /// The turn's steps, each `at` seconds after the turn started.
        let steps: [Step]?
        let edits: Int?
        /// The desktop app's plan, by status: `completed`, `in_progress`,
        /// `pending`.
        let plan: [String]?
        /// The permission prompt it waits on.
        let ask: Ask?
    }

    private struct Step: Decodable {
        let action: String
        let count: Int
        let at: Double
    }

    private struct Ask: Decodable {
        let tool: String
        let subject: String
    }

    private struct Sessions: Decodable {
        let sessions: [Session]
        /// The one asleep beside the notch, by id.
        let justFinished: String?
    }

    static func startIfRequested() {
        guard UserDefaults.standard.bool(forKey: "AIMeterIslandDirector") else { return }
        DistributedNotificationCenter.default().addObserver(forName: notification, object: nil, queue: .main) { note in
            let command = note.userInfo?["command"] as? String ?? ""
            let value = note.userInfo?["value"] as? String ?? ""
            Task { @MainActor in run(command, value) }
        }
    }

    @MainActor
    private static func run(_ command: String, _ value: String) {
        switch command {
        case "demo":
            guard let model = AppEnvironment.shared, !model.isDemoMode else { return }
            model.enterDemoMode()
        case "level":
            switch value {
            case "peek": AppChrome.notchIsland.direct(.peek)
            case "expanded": AppChrome.notchIsland.direct(.expanded)
            default: AppChrome.notchIsland.direct(.collapsed)
            }
        case "sessions":
            guard let data = value.data(using: .utf8),
                  let list = try? JSONDecoder().decode(Sessions.self, from: data) else { return }
            let now = Date()
            let activities = list.sessions.map { session in
                let at = now.addingTimeInterval(-session.ago)
                let state: ClaudeCodeSessionActivity.State = switch session.state {
                case "waiting": .needsPermission(since: at)
                case "finished": .finished(at: at)
                default: .working(since: at)
                }
                var activity = ClaudeCodeSessionActivity(id: session.id, customTitle: session.title, project: session.project, state: state, lastActivity: now)
                if let steps = session.steps {
                    // A finished session's turn ended `ago`; it started before.
                    let start = session.state == "finished" ? at.addingTimeInterval(-(steps.last?.at ?? 0) - 20) : at
                    activity.turn = ClaudeCodeTurn(
                        start: start,
                        steps: steps.compactMap { step in
                            ClaudeCodeTurn.Action(rawValue: step.action).map {
                                ClaudeCodeTurn.Step(action: $0, start: start.addingTimeInterval(step.at), count: step.count)
                            }
                        },
                        edits: session.edits ?? 0,
                        plan: session.plan?.map { status -> ClaudeCodeTurn.PlanStatus in
                            switch status {
                            case "completed": .completed
                            case "in_progress": .inProgress
                            default: .pending
                            }
                        }
                    )
                }
                return activity
            }
            let asks = Dictionary(uniqueKeysWithValues: list.sessions.compactMap { session in
                session.ask.map { (session.id, ClaudeCodePermissionAsk(sessionId: session.id, toolName: $0.tool, subject: $0.subject)) }
            })
            DemoSessions.shared.set(activities, justFinished: activities.first { $0.id == list.justFinished }, asks: asks)
        case "approve":
            DemoSessions.shared.approve(value)
        default:
            break
        }
    }
}
#endif
