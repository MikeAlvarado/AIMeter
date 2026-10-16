#if os(macOS)
import Foundation

/// The optional Claude Code hooks: one click adds AIMeter's command to the
/// events that say what a session is doing, in the user's own Claude Code
/// settings (`~/.claude/settings.json`, read by the CLI and the desktop
/// app alike, and picked up by running sessions without a restart), and
/// one click takes exactly those entries out again. Every other setting
/// and hook in the file is kept; the file is backed up before each change
/// (`settings.json.aimeter-backup`) and never written when it doesn't
/// parse. The command posts the event to `ClaudeHookListener`'s socket in
/// the background (`async`, so Claude Code never waits for it) and always
/// exits 0; with AIMeter closed it does nothing at all.
nonisolated enum ClaudeCodeHooks {
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
    static let toolEvents: Set<String> = ["PermissionRequest"]

    /// What makes an entry AIMeter's own, for "Remove".
    static let marker = "AIMeter/claude-hooks.sock"

    /// `sh -c`'d by Claude Code with the event's JSON on stdin. The socket
    /// test keeps it from even starting curl while AIMeter isn't running.
    static let command = #"[ -S "$HOME/Library/Application Support/AIMeter/claude-hooks.sock" ] && /usr/bin/curl -s -m 2 --unix-socket "$HOME/Library/Application Support/AIMeter/claude-hooks.sock" --data-binary @- http://localhost/claude-hook >/dev/null 2>&1 || true"#

    /// The handler AIMeter adds to each event.
    static var handler: [String: Any] {
        ["type": "command", "command": command, "async": true]
    }

    enum Failure: LocalizedError {
        case unreadable
        var errorDescription: String? {
            String(localized: "Claude Code's settings file isn't valid JSON, so AIMeter left it untouched.")
        }
    }

    // MARK: Pure

    /// Whether every event has AIMeter's current entry. One from an older
    /// build (another command, a different set of events) reads as not
    /// installed, so installing again replaces it.
    static func isInstalled(in settings: [String: Any]) -> Bool {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return events.allSatisfy { event in
            groups(hooks[event]).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String) == command }
            }
        }
    }

    /// `settings` with AIMeter's entry on every event, nothing else changed
    /// (its own older entries are replaced, never doubled).
    static func installing(into settings: [String: Any]) -> [String: Any] {
        var settings = removing(from: settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
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

    static var isInstalled: Bool {
        (try? read()).map(isInstalled(in:)) ?? false
    }

    static func install() throws {
        try write(installing(into: read()))
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
