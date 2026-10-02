import Foundation

/// Everything read from the logs so far: deduplicated messages, the
/// per-session totals Claude Code computed itself, and the per-file
/// offsets that make the next scan incremental. Persisted as one JSON
/// file (`indexURL`) so a relaunch doesn't re-read gigabytes.
public struct ClaudeCodeUsageLedger: Codable, Equatable, Sendable {
    public struct FileState: Codable, Equatable, Sendable {
        public var bytesParsed: Int
        /// Session id derived from the file name, for lines without one.
        public var sessionID: String
    }

    public var version = 1
    public var entries: [ClaudeCodeUsageEntry] = []
    public var sessionTotals: [String: ClaudeCodeSessionTotal] = [:]
    /// `messageID|requestID` of every message already counted — streaming
    /// writes the same message as several lines, and the duplicate can
    /// land on the other side of a scan boundary.
    public var seen: Set<String> = []
    public var files: [String: FileState] = [:]
    public var lastScanned: Date?

    public init() {}
}

/// Incremental reader of `~/.claude/projects/**/*.jsonl`. Each scan
/// enumerates the files and, per file, reads only the bytes appended
/// since the last scan — by **size**, not modification date (file
/// timestamps are a required-reason API; the size is not) — and
/// re-reads from zero when a file shrank (truncated or rewritten). A
/// partial last line (Claude Code mid-write) is left for the next scan.
/// Runs off the main actor; the first pass over a large history is the
/// only slow one.
public actor ClaudeCodeLogReader {
    public let root: URL
    public let indexURL: URL
    private var ledger: ClaudeCodeUsageLedger

    public init(root: URL, indexURL: URL) {
        self.root = root
        self.indexURL = indexURL
        ledger = Self.loadLedger(at: indexURL)
    }

    public func currentLedger() -> ClaudeCodeUsageLedger { ledger }

    /// Reads whatever is new and returns the whole ledger.
    public func scan(now: Date = Date()) -> ClaudeCodeUsageLedger {
        let files = Self.logFiles(under: root)
        var present: Set<String> = []
        for url in files {
            // Symlink-resolved so a root reached two ways keys one entry.
            let path = url.resolvingSymlinksInPath().path
            present.insert(path)
            let sessionID = url.deletingPathExtension().lastPathComponent
            var state = ledger.files[path] ?? .init(bytesParsed: 0, sessionID: sessionID)
            guard let size = Self.fileSize(url) else { continue }
            if size < state.bytesParsed {
                // Shrunk: whatever we counted from it is suspect. The
                // entries themselves stay (they were real messages when
                // read); the file is simply re-read from the start, and
                // dedupe keeps already-seen messages from counting twice.
                state.bytesParsed = 0
            }
            guard size > state.bytesParsed else { continue }
            let consumed = parse(url, from: state.bytesParsed, to: size, sessionID: sessionID)
            state.bytesParsed += consumed
            ledger.files[path] = state
        }
        // Files that vanished (a project folder deleted) keep their entries
        // but drop their offsets.
        ledger.files = ledger.files.filter { present.contains($0.key) }
        ledger.lastScanned = now
        saveLedger()
        return ledger
    }

    /// Returns how many bytes were consumed (complete lines only).
    private func parse(_ url: URL, from offset: Int, to end: Int, sessionID: String) -> Int {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(offset))) != nil,
              let data = try? handle.read(upToCount: end - offset), !data.isEmpty else { return 0 }
        // Only whole lines: a trailing fragment is still being written.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return 0 }
        let complete = data[data.startIndex...lastNewline]
        var cursor = complete.startIndex
        while cursor < complete.endIndex {
            let lineEnd = complete[cursor...].firstIndex(of: UInt8(ascii: "\n")) ?? complete.endIndex
            let line = complete[cursor..<lineEnd]
            cursor = min(lineEnd + 1, complete.endIndex)
            guard !line.isEmpty else { continue }
            switch ClaudeCodeLogLine.parse(Data(line), fallbackSessionID: sessionID) {
            case .assistant(let entry, let messageID, let requestID):
                let key = "\(messageID ?? "")|\(requestID ?? "")"
                if messageID != nil || requestID != nil {
                    guard ledger.seen.insert(key).inserted else { continue }
                }
                ledger.entries.append(entry)
            case .costState(let total):
                // Cumulative: the latest record for a session wins.
                ledger.sessionTotals[total.sessionID] = total
            case nil:
                continue
            }
        }
        return complete.count
    }

    // MARK: - Files

    static func logFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            found.append(url)
        }
        return found.sorted { $0.path < $1.path }
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    // MARK: - Persistence

    private static func loadLedger(at url: URL) -> ClaudeCodeUsageLedger {
        guard let data = try? Data(contentsOf: url) else { return ClaudeCodeUsageLedger() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ClaudeCodeUsageLedger.self, from: data)) ?? ClaudeCodeUsageLedger()
    }

    private func saveLedger() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(ledger) else { return }
        try? FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Forgets everything read; the next scan starts from zero.
    public func reset() {
        ledger = ClaudeCodeUsageLedger()
        try? FileManager.default.removeItem(at: indexURL)
    }
}
