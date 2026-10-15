#if os(macOS) && DEBUG
import AppKit
import UsageKit

/// `DEBUG` only: lets `Scripts/IslandVideo` drive the notch island while it
/// records the website's videos (see `Scripts/IslandVideo/CLAUDE.md`).
/// Launched with `-AIMeterIslandDirector YES`, the app takes commands as
/// distributed notifications (`notification`, a `command` and a `value`
/// in `userInfo`): `demo` turns demo mode on, `level` opens the island to
/// `collapsed`, `peek` or `expanded`, and `sessions` replaces the demo's
/// sessions with a JSON list. A recording needs no cursor and shows no
/// real session.
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
                return ClaudeCodeSessionActivity(id: session.id, customTitle: session.title, project: session.project, state: state, lastActivity: now)
            }
            DemoSessions.shared.set(activities, justFinished: activities.first { $0.id == list.justFinished })
        default:
            break
        }
    }
}
#endif
