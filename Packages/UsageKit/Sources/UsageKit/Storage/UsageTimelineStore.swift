import Foundation

/// A month of usage samples per window and account, kept for the history
/// chart — one JSON file per account in the App Group container
/// (`usage-timeline/<accountID>.json`), written wherever a fetch persists
/// a snapshot (the app and the iOS widget self-fetch, through
/// `UsageRecorder`). Distinct from `UsageHistoryStore`, whose series is
/// deliberately reset-*aware* (it discards the previous window so the
/// run-out predictor never spans a reset) and therefore useless for a
/// chart that exists to show several windows and their resets in a row.
///
/// Compacted on every write (`UsageTimeline.compacted`): raw for 48 hours,
/// one sample per hour before that, nothing past 30 days — tens of KB per
/// account at the 30-minute cadence. Writes are atomic; the app and the
/// widget may both append, and the rare lost sample is accepted over a
/// lock.
public struct UsageTimelineStore: Sendable {
    public static let retention: TimeInterval = 30 * 24 * 3600
    public static let rawWindow: TimeInterval = 48 * 3600

    private let directory: URL

    /// The App Group container's `usage-timeline/` folder; nil when the
    /// container can't be resolved (no entitlement, or a unit test host).
    public init?(appGroupID: String) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        self.init(directory: container.appendingPathComponent("usage-timeline", isDirectory: true))
    }

    public init(directory: URL) {
        self.directory = directory
    }

    /// Time-ordered samples for one window kind, optionally only from
    /// `since` on.
    public func samples(for accountID: String, kind: UsageWindow.Kind, since: Date? = nil) -> [TimelineSample] {
        let all = load(accountID).kinds[kind.storageKey] ?? []
        guard let since else { return all }
        return all.filter { $0.timestamp >= since }
    }

    /// Every kind's samples, keyed by `UsageWindow.Kind.storageKey`.
    public func allSamples(for accountID: String) -> [String: [TimelineSample]] {
        load(accountID).kinds
    }

    /// Appends one sample per window in the snapshot and compacts.
    public func record(_ snapshot: UsageSnapshot, for accountID: String, at now: Date = Date()) {
        var file = load(accountID)
        for window in snapshot.windows {
            let key = window.kind.storageKey
            var series = file.kinds[key] ?? []
            series.append(TimelineSample(timestamp: now, usedPct: window.usedPct, resetsAt: window.resetsAt))
            file.kinds[key] = UsageTimeline.compacted(series, now: now, rawWindow: Self.rawWindow, retention: Self.retention)
        }
        save(file, for: accountID)
    }

    public func clear(for accountID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: accountID))
    }

    // MARK: - Persistence

    private struct TimelineFile: Codable {
        var version = 1
        var kinds: [String: [TimelineSample]] = [:]
    }

    private func fileURL(for accountID: String) -> URL {
        directory.appendingPathComponent("\(accountID).json", isDirectory: false)
    }

    private func load(_ accountID: String) -> TimelineFile {
        guard let data = try? Data(contentsOf: fileURL(for: accountID)) else { return TimelineFile() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A file that doesn't decode (a future version, or damage) starts
        // over rather than taking the chart down with it.
        return (try? decoder.decode(TimelineFile.self, from: data)) ?? TimelineFile()
    }

    private func save(_ file: TimelineFile, for accountID: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: accountID), options: .atomic)
    }
}
