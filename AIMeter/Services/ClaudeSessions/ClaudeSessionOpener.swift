#if os(macOS)
import AppKit

/// "Open" on a session in the island: brings up the window the session
/// lives in, in the right copy of Claude when there are several (a Mac may
/// have Claude and Claude Work, which both answer `claude://` links, so a
/// link opened the ordinary way could land in the other one).
///
/// A desktop app keeps a small record per session in its own Application
/// Support folder (`claude-code-sessions/…/local_<id>.json`), whose
/// `cliSessionId` is the log's session id and `sessionId` the app's own:
/// the folder names the copy (`Claude`, `Claude Work`, the same name as
/// the app's bundle) and its `claude://code/continue?session=local_<id>`
/// link, opened with that copy, shows the session (measured on 2026-10-23
/// with Claude Work). Only those two ids are decoded. A session from a
/// terminal has no record: the hooks say which Claude Code process it is
/// (`ppid`), and the first app among that process's ancestors (the
/// terminal, or the desktop app that runs it) comes forward.
@MainActor
final class ClaudeSessionOpener {
    /// A desktop app's session: which copy, and its own id.
    nonisolated struct Place: Equatable, Sendable {
        let app: URL
        let localID: String
    }

    private var places: [String: Place] = [:]
    private var scanning = false
    private var lastScan: Date = .distantPast

    /// Where `session` opens, from the last scan.
    func place(of session: String) -> Place? {
        places[session]
    }

    /// Reads the desktop apps' records again, off the main thread, when a
    /// session shown has none yet (at most every 10 s); `done` runs once
    /// the new places are in.
    func refresh(for sessions: [String], done: @escaping @MainActor () -> Void) {
        guard !scanning, sessions.contains(where: { places[$0] == nil }),
              Date().timeIntervalSince(lastScan) > 10 else { return }
        scanning = true
        lastScan = Date()
        let apps = Self.claudeApps()
        Task.detached(priority: .utility) {
            let found = Self.scan(apps: apps)
            await MainActor.run {
                self.places = found
                self.scanning = false
                done()
            }
        }
    }

    /// Opens `session`: its desktop app's link, else the app the Claude Code
    /// process `pid` runs under. False when neither is known.
    @discardableResult
    func open(_ session: String, pid: Int32?) -> Bool {
        if let place = places[session],
           let link = URL(string: "claude://code/continue?session=\(place.localID)") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([link], withApplicationAt: place.app, configuration: configuration)
            return true
        }
        if let pid, let app = Self.owningApp(of: pid) {
            return app.activate()
        }
        return false
    }

    // MARK: Desktop apps

    /// The apps that answer `claude://` links, by their name.
    nonisolated static func claudeApps() -> [String: URL] {
        guard let scheme = URL(string: "claude://") else { return [:] }
        var apps: [String: URL] = [:]
        for url in NSWorkspace.shared.urlsForApplications(toOpen: scheme) {
            apps[url.deletingPathExtension().lastPathComponent] = apps[url.deletingPathExtension().lastPathComponent] ?? url
        }
        return apps
    }

    /// Every desktop app's records: the log's session id to its place.
    nonisolated static func scan(apps: [String: URL]) -> [String: Place] {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        var places: [String: Place] = [:]
        for (name, app) in apps {
            let root = support.appendingPathComponent(name).appendingPathComponent("claude-code-sessions")
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let record = try? JSONDecoder().decode(Record.self, from: data) else { continue }
                places[record.cliSessionId] = Place(app: app, localID: record.sessionId)
            }
        }
        return places
    }

    /// A desktop app's session record, its two ids and nothing else.
    nonisolated struct Record: Decodable, Equatable {
        let sessionId: String
        let cliSessionId: String
    }

    // MARK: Processes

    /// The first app with a window among `pid`'s ancestors, `pid` included.
    nonisolated static func owningApp(of pid: Int32) -> NSRunningApplication? {
        var current: Int32? = pid
        var steps = 0
        while let candidate = current, steps < 32 {
            if let app = NSRunningApplication(processIdentifier: candidate), app.activationPolicy == .regular {
                return app
            }
            current = parent(of: candidate)
            steps += 1
        }
        return nil
    }

    nonisolated static func parent(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 1 ? parent : nil
    }
}
#endif
