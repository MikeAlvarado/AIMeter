#if os(macOS)
import CoreServices
import Foundation
import UsageKit

/// Follows `~/.claude/projects` as Claude Code writes it: an FSEvents
/// stream reports which session logs changed, and only the bytes added
/// since the last read are parsed (`ClaudeCodeSessionRecord`, which
/// decodes the record's shape and never its content). A log seen for the
/// first time is read from its last 256 KB and, for a session's own log,
/// further back (4× at a time, up to 16 MB) until it holds the end of a
/// turn, so the turn after it is read from its start: a long turn
/// otherwise counted its time from wherever the window began ("Working
/// for 3m" for a session at work for half an hour, seen when AIMeter
/// launched). Like the usage reader, it keys a
/// file by size and offset, never by modification date. Runs on its own
/// queue; batches of records are handed to `deliver` on the main actor.
nonisolated final class ClaudeSessionLogWatcher: @unchecked Sendable {
    struct Batch: Sendable {
        let sessionID: String
        /// The subagent whose log it is, nil for the session's own.
        let agentID: String?
        let records: [ClaudeCodeSessionRecord]
    }

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    static let firstReadLimit: UInt64 = 256 * 1024
    static let firstReadCap: UInt64 = 16 * 1024 * 1024

    private let root: URL
    private let deliver: @MainActor ([Batch]) -> Void
    private let queue = DispatchQueue(label: "com.mikealvarado.aimeter.claude-sessions", qos: .utility)
    private var stream: FSEventStreamRef?
    /// Per log: how far it has been read, and a trailing partial line.
    private var offsets: [String: UInt64] = [:]
    private var remainders: [String: Data] = [:]

    init(root: URL = ClaudeSessionLogWatcher.defaultRoot, deliver: @escaping @MainActor ([Batch]) -> Void) {
        self.root = root
        self.deliver = deliver
    }

    deinit { tearDown() }

    var rootExists: Bool {
        FileManager.default.fileExists(atPath: root.path)
    }

    func start() {
        guard stream == nil, rootExists else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ClaudeSessionLogWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            watcher.changed(Array(list.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            nil, callback, &context, [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.4, flags
        ) else { return }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    func stop() {
        tearDown()
        queue.async { [weak self] in
            self?.offsets.removeAll()
            self?.remainders.removeAll()
        }
    }

    private func tearDown() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// On the watcher's queue.
    private func changed(_ paths: [String]) {
        var batches: [Batch] = []
        // Sorted, a session's own log ("<id>.jsonl") comes before its
        // subagents' ("<id>/subagents/…"): the turn's start is read first,
        // and what a subagent wrote before the turn ended is then old news.
        for path in Set(paths).sorted() {
            guard let owner = Self.owner(of: path) else { continue }
            let records = read(URL(fileURLWithPath: path), ownLog: owner.agent == nil)
            if !records.isEmpty {
                batches.append(Batch(sessionID: owner.session, agentID: owner.agent, records: records))
            }
        }
        guard !batches.isEmpty else { return }
        let deliver = deliver
        let delivered = batches
        Task { @MainActor in deliver(delivered) }
    }

    /// Whose log a path is: `<session>.jsonl` is the session's own, and an
    /// `agent-<id>.jsonl` anywhere under `<session>/subagents/` (workflow
    /// agents nest a level deeper) a subagent's, which speaks for the
    /// session that started it. Anything else (a workflow's journal) is
    /// nobody's.
    static func owner(of path: String) -> (session: String, agent: String?)? {
        let components = path.split(separator: "/").map(String.init)
        guard let name = components.last, name.hasSuffix(".jsonl") else { return nil }
        let base = String(name.dropLast(".jsonl".count))
        guard let marker = components.lastIndex(of: "subagents") else { return (base, nil) }
        guard marker > 0, base.hasPrefix("agent-") else { return nil }
        return (components[marker - 1], String(base.dropFirst("agent-".count)))
    }

    /// The complete lines added to `file` since the last read.
    private func read(_ file: URL, ownLog: Bool) -> [ClaudeCodeSessionRecord] {
        let path = file.path
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            offsets[path] = nil
            remainders[path] = nil
            return []
        }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        guard let offset = offsets[path], offset <= size else {
            // Seen for the first time, or rewritten from scratch.
            remainders[path] = nil
            offsets[path] = size
            return firstRead(handle, path: path, size: size, ownLog: ownLog)
        }
        offsets[path] = size
        guard offset < size, (try? handle.seek(toOffset: offset)) != nil, let added = try? handle.readToEnd() else { return [] }
        let data = (remainders[path] ?? Data()) + added
        remainders[path] = nil
        return records(in: data, path: path, dropsFirstLine: false)
    }

    /// A log's tail, widened until it holds the previous turn's end (see
    /// the type doc). Only a session's own log needs it: a subagent's
    /// records only ever say its parent is working.
    private func firstRead(_ handle: FileHandle, path: String, size: UInt64, ownLog: Bool) -> [ClaudeCodeSessionRecord] {
        var window = Self.firstReadLimit
        while true {
            let start = size > window ? size - window : 0
            guard (try? handle.seek(toOffset: start)) != nil, let tail = try? handle.read(upToCount: Int(size - start)) else { return [] }
            remainders[path] = nil
            let found = records(in: tail, path: path, dropsFirstLine: start > 0)
            if start == 0 || !ownLog || window >= Self.firstReadCap || found.contains(where: \.endsTurn) {
                return found
            }
            window *= 4
        }
    }

    /// The records in `data`'s complete lines; a trailing partial line is
    /// kept for the next read, and a first line cut by the window dropped.
    private func records(in data: Data, path: String, dropsFirstLine: Bool) -> [ClaudeCodeSessionRecord] {
        var data = data
        if let lastBreak = data.lastIndex(of: UInt8(ascii: "\n")) {
            if lastBreak < data.index(before: data.endIndex) {
                remainders[path] = data[data.index(after: lastBreak)...]
                data = data[..<data.index(after: lastBreak)]
            }
        } else {
            if !dropsFirstLine { remainders[path] = data }
            return []
        }
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if dropsFirstLine, !lines.isEmpty { lines.removeFirst() }
        return lines.compactMap { ClaudeCodeSessionRecord.parse(Data($0)) }
    }
}
#endif
