import Foundation

/// One video: what the app is told when, and where the drawn cursor is.
/// Times are seconds from the first recorded frame; the canvas is
/// `Scene.canvas` points with the notch at the top centre.
struct Scene {
    static let canvas = CGSize(width: 960, height: 540)
    static let fps = 30

    enum Cue {
        case level(String)
        case sessions([Session], justFinished: String? = nil)
        /// The card's Approve on that session's prompt.
        case approve(String)
    }

    struct Session: Encodable {
        let id: String
        let title: String?
        let project: String?
        let state: String
        let ago: Double
        /// The turn's steps for the card: an action (`ClaudeCodeTurn.Action`),
        /// how many in a row, and when, in seconds from the turn's start.
        var steps: [Step]? = nil
        var edits: Int? = nil
        var plan: [String]? = nil
        var ask: Ask? = nil
    }

    struct Step: Encodable {
        let action: String
        let count: Int
        let at: Double
    }

    struct Ask: Encodable {
        let tool: String
        let subject: String
    }

    /// Steps from (action, count, seconds after the start) triples.
    static func steps(_ list: [(String, Int, Double)]) -> [Step] {
        list.map { Step(action: $0.0, count: $0.1, at: $0.2) }
    }

    /// A cursor keyframe: where its tip is at `time` (nil hides it), and
    /// whether it clicks there.
    struct Key {
        let time: Double
        let point: CGPoint?
        var click = false
    }

    let name: String
    let duration: Double
    /// What the island shows before the first frame.
    let setup: [Cue]
    let cues: [(time: Double, cue: Cue)]
    let cursor: [Key]

    static func named(_ name: String, language: String) -> Scene? {
        let es = language == "es"
        let notch = CGPoint(x: canvas.width / 2 + 14, y: 15)
        let rest = CGPoint(x: 650, y: 360)
        let away = CGPoint(x: 700, y: 420)
        // Where it rests on the open island: right of the second account's
        // name, clear of every figure.
        let inside = CGPoint(x: notch.x + 30, y: 118)
        let onboarding = es ? "Terminar el onboarding" : "Ship the onboarding"
        let apiClient = es ? "Refactorizar el cliente de la API" : "Refactor the API client"
        switch name {
        case "limits":
            // No session at work: resting on the notch peeks the figures,
            // a click opens every account.
            return Scene(
                name: name, duration: 11,
                setup: [.sessions([]), .level("collapsed")],
                cues: [(2.2, .level("peek")), (4.4, .level("expanded")), (8.6, .level("collapsed"))],
                cursor: [
                    Key(time: 0, point: rest), Key(time: 0.8, point: rest), Key(time: 1.9, point: notch),
                    Key(time: 4.4, point: notch, click: true), Key(time: 5.4, point: inside),
                    Key(time: 8.0, point: inside), Key(time: 8.9, point: away), Key(time: 11, point: away),
                ]
            )
        case "sessions":
            // Two sessions at work walk beside the notch; resting on it
            // shows the newest in full, a click every session, the newest
            // as its card: what it does now, what it did, "Step 3 of 5".
            // Two, not more: the open island with the card and its accounts
            // is then just short of the canvas's height.
            let sessions = [
                Session(id: "demo-54", title: onboarding, project: "my-app", state: "working", ago: 65,
                        steps: Self.steps([("thinking", 1, 0), ("reading", 3, 6), ("editing", 2, 21), ("running", 1, 44)]),
                        edits: 2, plan: ["completed", "completed", "in_progress", "pending", "pending"]),
                Session(id: "demo-425", title: apiClient, project: "backend", state: "working", ago: 305,
                        steps: Self.steps([("reading", 5, 0), ("editing", 4, 90), ("running", 2, 210)]), edits: 4),
            ]
            return Scene(
                name: name, duration: 12,
                setup: [.sessions(sessions), .level("collapsed")],
                cues: [(3.0, .level("peek")), (5.2, .level("expanded")), (9.4, .level("collapsed"))],
                cursor: [
                    Key(time: 0, point: away), Key(time: 1.6, point: away), Key(time: 2.7, point: notch),
                    Key(time: 5.2, point: notch, click: true), Key(time: 6.2, point: inside),
                    Key(time: 8.8, point: inside), Key(time: 9.7, point: away), Key(time: 12, point: away),
                ]
            )
        case "permission":
            // A session asks for permission: its pet comes forward and
            // shakes beside its "!". Resting on the notch says so, a click
            // opens its card, which says what it asks; Approve on the card
            // and it works on, and another finishes and falls asleep.
            let foxSteps = Self.steps([("reading", 4, 0), ("searching", 2, 40), ("editing", 3, 65), ("running", 1, 265)])
            // Two sessions, the card and one row, so the open island fits.
            func two(fox: String, foxAgo: Double, cat: String = "working") -> [Session] {
                [
                    Session(id: "demo-170", title: apiClient, project: "backend", state: fox, ago: foxAgo,
                            steps: foxSteps, edits: 3,
                            ask: fox == "waiting" ? Ask(tool: "Bash", subject: "npm run db:migrate") : nil),
                    Session(id: "demo-54", title: onboarding, project: "my-app", state: cat, ago: cat == "working" ? 95 : 0,
                            steps: Self.steps([("reading", 3, 0), ("editing", 2, 30)]), edits: 2),
                ]
            }
            // The card's Approve, measured on a MacBook's island: left of
            // the card's footer, under the accounts.
            let approve = CGPoint(x: canvas.width / 2 - 127, y: 409)
            return Scene(
                name: name, duration: 15,
                setup: [.sessions(two(fox: "working", foxAgo: 300)), .level("collapsed")],
                cues: [
                    (1.8, .sessions(two(fox: "waiting", foxAgo: 280))),
                    (4.0, .level("peek")),
                    (6.0, .level("expanded")),
                    (8.4, .approve("demo-170")),
                    (11.0, .level("collapsed")),
                    (12.2, .sessions(two(fox: "working", foxAgo: 290, cat: "finished"), justFinished: "demo-54")),
                ],
                cursor: [
                    Key(time: 0, point: rest), Key(time: 2.8, point: rest), Key(time: 3.7, point: notch),
                    Key(time: 6.0, point: notch, click: true), Key(time: 7.4, point: approve),
                    Key(time: 8.4, point: approve, click: true), Key(time: 9.4, point: inside),
                    Key(time: 10.4, point: inside), Key(time: 11.2, point: away), Key(time: 15, point: away),
                ]
            )
        default:
            return nil
        }
    }

    /// The cursor at `time`: eased between keyframes; a click shows as a
    /// ring for a third of a second after its key.
    func cursor(at time: Double) -> (point: CGPoint?, ring: Double?) {
        guard let next = cursor.firstIndex(where: { $0.time > time }) else { return (cursor.last?.point, nil) }
        let ring = cursor.last { $0.click && $0.time <= time && time - $0.time < 0.35 }.map { (time - $0.time) / 0.35 }
        guard next > 0 else { return (cursor.first?.point, ring) }
        let a = cursor[next - 1], b = cursor[next]
        guard let from = a.point, let to = b.point else { return (a.point, ring) }
        let x = (time - a.time) / (b.time - a.time)
        let eased = x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
        return (CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased), ring)
    }
}
