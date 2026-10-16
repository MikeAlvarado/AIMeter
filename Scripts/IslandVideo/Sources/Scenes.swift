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
    }

    struct Session: Encodable {
        let id: String
        let title: String?
        let project: String?
        let state: String
        let ago: Double
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
        let notes = es ? "Escribir las notas de la versión" : "Write the release notes"
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
            // Three sessions at work walk beside the notch; resting on it
            // shows the newest in full, a click every session.
            let sessions = [
                Session(id: "demo-54", title: onboarding, project: "my-app", state: "working", ago: 65),
                Session(id: "demo-203", title: nil, project: "website", state: "working", ago: 185),
                Session(id: "demo-425", title: apiClient, project: "backend", state: "working", ago: 305),
                Session(id: "demo-70", title: notes, project: "docs", state: "finished", ago: 125),
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
            // shakes beside a yellow "!". Resting on the notch says so,
            // a click shows where; once allowed it works on, and another
            // finishes and falls asleep.
            func three(fox: String, foxAgo: Double, bunny: String = "working") -> [Session] {
                [
                    Session(id: "demo-170", title: apiClient, project: "backend", state: fox, ago: foxAgo),
                    Session(id: "demo-54", title: onboarding, project: "my-app", state: "working", ago: 95),
                    Session(id: "demo-203", title: nil, project: "website", state: bunny, ago: bunny == "working" ? 215 : 0),
                ]
            }
            return Scene(
                name: name, duration: 14,
                setup: [.sessions(three(fox: "working", foxAgo: 300)), .level("collapsed")],
                cues: [
                    (1.8, .sessions(three(fox: "waiting", foxAgo: 0))),
                    (4.0, .level("peek")),
                    (6.0, .level("expanded")),
                    (8.6, .sessions(three(fox: "working", foxAgo: 0))),
                    (10.0, .level("collapsed")),
                    (11.2, .sessions(three(fox: "working", foxAgo: 3, bunny: "finished"), justFinished: "demo-203")),
                ],
                cursor: [
                    Key(time: 0, point: rest), Key(time: 2.8, point: rest), Key(time: 3.7, point: notch),
                    Key(time: 6.0, point: notch, click: true), Key(time: 7.0, point: inside),
                    Key(time: 9.4, point: inside), Key(time: 10.2, point: away), Key(time: 14, point: away),
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
