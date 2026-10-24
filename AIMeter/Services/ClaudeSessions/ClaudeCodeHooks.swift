#if os(macOS)
import Foundation

/// The optional Claude Code hooks: one click adds AIMeter's command to the
/// events that say what a session is doing, in the user's own Claude Code
/// settings (`~/.claude/settings.json`, read by the CLI and the desktop
/// app alike, and picked up by running sessions without a restart), and
/// one click takes exactly those entries out again. Every other setting
/// and hook in the file is kept; the file is backed up before each change
/// (`settings.json.aimeter-backup`) and never written when it doesn't
/// parse. Each command posts the event to `ClaudeHookListener`'s socket,
/// with the id of the Claude Code process that ran it (which app or
/// terminal a session lives in), and always exits 0; with AIMeter closed
/// it does nothing at all.
///
/// Two modes. Watching (the hooks alone): every command is `async`, so
/// Claude Code never waits for it. Answering ("Answer from the island",
/// off by default): the permission request's command waits for the
/// user's answer in the island and prints it, and a `PreToolUse` command
/// asks whether the user stopped the session before each tool (a few
/// milliseconds). Claude Code shows its own prompt meanwhile, and
/// whichever is answered first decides (measured on 2026-10-23 with
/// Claude Code 2.1.306); a command that prints nothing, as it does with
/// AIMeter closed, leaves the prompt to Claude Code.
nonisolated enum ClaudeCodeHooks {
    enum Mode: Equatable { case watching, answering }

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// The events AIMeter listens to, the few the log can't tell as soon
    /// or at all: a prompt (a turn starts), a permission request (the
    /// session waits for the user), a notification (the idle one ends a
    /// turn the log missed), a turn's end, a failed one, and the session's
    /// end. The log says the rest, the answer to a prompt included.
    static let events = ["UserPromptSubmit", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]
    /// The events whose entries carry a tool `matcher`.
    static let toolEvents: Set<String> = ["PermissionRequest", "PreToolUse"]

    /// What makes an entry AIMeter's own, for "Remove".
    static let marker = "AIMeter/claude-hooks.sock"

    private static let socket = #""$HOME/Library/Application Support/AIMeter/claude-hooks.sock""#

    /// `sh -c`'d by Claude Code with the event's JSON on stdin. The socket
    /// test keeps it from even starting curl while AIMeter isn't running.
    /// `$PPID` is the Claude Code process the hook runs under.
    static let command = #"[ -S \#(socket) ] && /usr/bin/curl -s -m 2 --unix-socket \#(socket) --data-binary @- "http://localhost/claude-hook?ppid=$PPID" >/dev/null 2>&1 || true"#

    /// The permission request's command while answering: prints AIMeter's
    /// answer, or nothing (the island closed, the prompt answered in
    /// Claude Code, ten minutes gone).
    static let permissionCommand = #"[ -S \#(socket) ] && /usr/bin/curl -s -m 590 --unix-socket \#(socket) --data-binary @- "http://localhost/claude-permission?ppid=$PPID" 2>/dev/null; exit 0"#

    /// Before each tool while answering: prints the stop the user asked
    /// for in the island, else nothing.
    static let preToolCommand = #"[ -S \#(socket) ] && /usr/bin/curl -s -m 2 --unix-socket \#(socket) --data-binary @- "http://localhost/claude-pretool?ppid=$PPID" 2>/dev/null; exit 0"#

    /// Each event's handler in `mode`.
    static func handlers(_ mode: Mode) -> [String: [String: Any]] {
        var handlers: [String: [String: Any]] = [:]
        for event in events {
            handlers[event] = ["type": "command", "command": command, "async": true]
        }
        if mode == .answering {
            handlers["PermissionRequest"] = ["type": "command", "command": permissionCommand, "timeout": 600]
            handlers["PreToolUse"] = ["type": "command", "command": preToolCommand, "timeout": 5]
        }
        return handlers
    }

    enum Failure: LocalizedError {
        case unreadable
        var errorDescription: String? {
            String(localized: "Claude Code's settings file isn't valid JSON, so AIMeter left it untouched.")
        }
    }

    // MARK: Pure

    /// The mode AIMeter's current entries are in, nil when they aren't all
    /// there. An entry from an older build (another command, another set of
    /// events) reads as nil, so installing again replaces it.
    static func installedMode(in settings: [String: Any]) -> Mode? {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        let ours = Dictionary(uniqueKeysWithValues: hooks.compactMap { event, value -> (String, String)? in
            let commands = groups(value).filter(isOurs).flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            guard commands.count == 1, let command = commands.first?["command"] as? String else { return nil }
            return (event, command)
        })
        for mode in [Mode.answering, .watching] {
            let expected = handlers(mode).mapValues { $0["command"] as? String ?? "" }
            if ours == expected { return mode }
        }
        return nil
    }

    static func isInstalled(in settings: [String: Any]) -> Bool {
        installedMode(in: settings) != nil
    }

    /// Whether the file has any entry of AIMeter's, current or not.
    static func hasEntries(in settings: [String: Any]) -> Bool {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return hooks.values.contains { groups($0).contains(where: isOurs) }
    }

    /// `settings` with AIMeter's entries in `mode`, nothing else changed
    /// (its own older entries are replaced, never doubled).
    static func installing(_ mode: Mode = .watching, into settings: [String: Any]) -> [String: Any] {
        var settings = removing(from: settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, handler) in handlers(mode).sorted(by: { $0.key < $1.key }) {
            var entry: [String: Any] = ["hooks": [handler]]
            if toolEvents.contains(event) { entry["matcher"] = "*" }
            hooks[event] = groups(hooks[event]) + [entry]
        }
        settings["hooks"] = hooks
        return settings
    }

    /// `settings` without AIMeter's entries; an event left empty, and a
    /// `hooks` left empty, go too.
    static func removing(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            let kept = groups(value).filter { !isOurs($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    private static func groups(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains {
            ($0["command"] as? String)?.contains(marker) == true
        }
    }

    // MARK: File

    /// What the file holds: AIMeter's entries in a mode, and whether it has
    /// any of its entries at all (an older build's, to bring up to date).
    static func state() -> (mode: Mode?, hasEntries: Bool) {
        guard let settings = try? read() else { return (nil, false) }
        return (installedMode(in: settings), hasEntries(in: settings))
    }

    static func install(_ mode: Mode) throws {
        try write(installing(mode, into: read()))
    }

    /// Takes AIMeter's entries out. When nothing else changed since the
    /// install, that is exactly the file the install backed up: it goes
    /// back byte for byte, formatting and key order included, and the
    /// backup with it.
    static func uninstall() throws {
        let result = removing(from: try read())
        if let original = try? Data(contentsOf: backupURL),
           let backup = try? JSONSerialization.jsonObject(with: original) as? [String: Any],
           NSDictionary(dictionary: backup).isEqual(to: result) {
            try write(original)
            try? FileManager.default.removeItem(at: backupURL)
            return
        }
        try write(result)
    }

    private static func read() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL), !data.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.unreadable }
        return object
    }

    static var backupURL: URL {
        settingsURL.appendingPathExtension("aimeter-backup")
    }

    private static func write(_ settings: [String: Any]) throws {
        try write(JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
    }

    /// Writes the file whole, in one step, with the permissions it had:
    /// Claude Code keeps it readable by its owner alone (it may carry
    /// environment variables with secrets), and a plain atomic write would
    /// recreate it readable by every user of the Mac. The new contents go
    /// to a file beside it, created with those permissions, which then
    /// takes its name. A `settings.json` that is a symbolic link (a dotfiles
    /// folder) is written where it points, so the link stays a link, and
    /// its permissions and the backup are the real file's, not the link's.
    private static func write(_ data: Data) throws {
        let fileManager = FileManager.default
        let target = settingsURL.resolvingSymlinksInPath()
        let folder = target.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var permissions = 0o600
        if fileManager.fileExists(atPath: target.path) {
            if let existing = try? fileManager.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int {
                permissions = existing
            }
            try? fileManager.removeItem(at: backupURL)
            try fileManager.copyItem(at: target, to: backupURL)
        }
        let staged = folder.appendingPathComponent(".settings.json.aimeter-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: staged.path, contents: data, attributes: [.posixPermissions: permissions]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(staged.path, target.path) == 0 else {
            try? fileManager.removeItem(at: staged)
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
#endif
