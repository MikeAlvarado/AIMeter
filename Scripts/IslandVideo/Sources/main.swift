import AppKit

// island-video <scene> <output .mov> [en|es]
//
// Records one of the website's notch island videos from the running app,
// which must be a DEBUG build launched with `-AIMeterIslandDirector YES`
// (see CLAUDE.md): demo mode, the scene's sessions and levels sent to it as
// it records, its panel captured alone and composed over a drawn desktop
// with a drawn cursor. Scripts/island-video.sh runs every scene and
// encodes the results.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: island-video <limits|sessions|permission> <output.mov> [en|es]")
    exit(2)
}
let language = arguments.count > 3 ? arguments[3] : "en"
guard let scene = Scene.named(arguments[1], language: language) else {
    print("unknown scene \(arguments[1])")
    exit(2)
}
let output = URL(fileURLWithPath: arguments[2])

/// The app's director (`IslandDirector`, DEBUG builds only).
func send(_ command: String, _ value: String = "") {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.mikealvarado.aimeter.director"), object: nil,
        userInfo: ["command": command, "value": value], deliverImmediately: true
    )
}

func send(_ cue: Scene.Cue) {
    switch cue {
    case .level(let level):
        send("level", level)
    case .sessions(let sessions, let justFinished):
        struct Payload: Encodable {
            let sessions: [Scene.Session]
            let justFinished: String?
        }
        let data = try! JSONEncoder().encode(Payload(sessions: sessions, justFinished: justFinished))
        send("sessions", String(decoding: data, as: UTF8.self))
    case .approve(let id):
        send("approve", id)
    }
}

func run() async throws {
    send("demo")
    try await Task.sleep(for: .seconds(1))
    scene.setup.forEach(send)
    // The island settles into the scene's first state before recording.
    try await Task.sleep(for: .seconds(1.5))
    let capture = PanelCapture()
    try await capture.start(bundleID: "com.mikealvarado.aimeter")
    for _ in 0..<60 where capture.latest == nil {
        try await Task.sleep(for: .milliseconds(50))
    }
    let backdrop = Backdrop.render(size: Scene.canvas, scale: 2, language: language)
    let writer = try FrameWriter(url: output, canvas: Scene.canvas, scale: 2)
    var pending = scene.cues
    let start = ContinuousClock.now
    let frames = Int(scene.duration * Double(Scene.fps))
    for frame in 0..<frames {
        let time = Double(frame) / Double(Scene.fps)
        try await Task.sleep(until: start + .milliseconds(Int(time * 1000)), clock: .continuous)
        while let next = pending.first, next.time <= time {
            send(next.cue)
            pending.removeFirst()
        }
        let cursor = scene.cursor(at: time)
        writer.append(
            frame: frame, backdrop: backdrop, panel: capture.latest, panelSize: capture.pointSize,
            anchorOffset: capture.anchorOffset, cursor: cursor.point, ring: cursor.ring
        )
    }
    await writer.finish()
    await capture.stop()
    print("wrote \(output.path): \(frames) frames, panel at \(capture.scale)x")
}

do {
    try await run()
} catch {
    print("island-video: \(error)")
    exit(1)
}
