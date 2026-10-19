import Foundation

/// One observation of a window kept for the history chart — unlike
/// `UsageSample` (the run-out predictor's unit) it also carries the
/// window's reset date, the strongest signal that a new window began.
/// Short coding keys: a month of these lives in a file per account.
public struct TimelineSample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let usedPct: Double
    public let resetsAt: Date?

    public init(timestamp: Date, usedPct: Double, resetsAt: Date?) {
        self.timestamp = timestamp
        self.usedPct = usedPct
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey {
        case timestamp = "t", usedPct = "u", resetsAt = "r"
    }
}

/// The pure rules over a timeline: where the windows reset, and how a long
/// series is thinned without losing those boundaries. Shared by the store
/// (compaction at write time) and the chart (segments at read time).
public enum UsageTimeline {
    /// A used% fall of at least this many points between consecutive
    /// samples is a reset — the same figure `UsageHistoryStore` uses.
    public static let resetDropThreshold = UsageHistoryStore.resetDropThreshold
    /// `resetsAt` moving later by more than this is a new window; the
    /// endpoint reports microsecond jitter on what is one boundary.
    public static let resetDateTolerance: TimeInterval = 60
    /// Two samples closer than this are one refresh recorded twice: on iOS
    /// the app and its widget both fetch when the app comes forward, and
    /// each writes what it got — often within the same second, which the
    /// file's whole-second dates then make identical. The later one stands.
    public static let sameRefreshWindow: TimeInterval = 60

    /// `series` with `sample` added: in place of the last sample when that
    /// one is the same refresh (`sameRefreshWindow`), after it otherwise.
    public static func appending(_ sample: TimelineSample, to series: [TimelineSample]) -> [TimelineSample] {
        var series = series
        if let last = series.last, isSameRefresh(last.timestamp, sample.timestamp) {
            series[series.count - 1] = sample
        } else {
            series.append(sample)
        }
        return series
    }

    /// One sample per refresh, for series written before `appending` kept
    /// them that way: a sample followed by the same refresh gives way to it.
    public static func deduplicated(_ samples: [TimelineSample]) -> [TimelineSample] {
        samples.indices.compactMap { index in
            let next = samples.index(after: index)
            guard next < samples.endIndex, isSameRefresh(samples[index].timestamp, samples[next].timestamp) else {
                return samples[index]
            }
            return nil
        }
    }

    static func isSameRefresh(_ a: Date, _ b: Date) -> Bool {
        abs(b.timeIntervalSince(a)) < sameRefreshWindow
    }

    /// Two devices' series of one window as one, for iCloud sync: every
    /// sample of both in time order, a refresh both recorded (within
    /// `sameRefreshWindow`) once, the later one standing. The result is
    /// the same whichever side is `a`, so two devices merging each
    /// other's series converge; the caller compacts it.
    public static func merged(_ a: [TimelineSample], _ b: [TimelineSample]) -> [TimelineSample] {
        let all = (a + b).sorted { lhs, rhs in
            lhs.timestamp != rhs.timestamp ? lhs.timestamp < rhs.timestamp : lhs.usedPct < rhs.usedPct
        }
        var result: [TimelineSample] = []
        for sample in all {
            if let last = result.last, isSameRefresh(last.timestamp, sample.timestamp) {
                result[result.count - 1] = sample
            } else {
                result.append(sample)
            }
        }
        return result
    }

    /// True when `current` belongs to a later window than `previous`:
    /// either its reset date moved on (weekly boundaries are fixed
    /// anchors, so this is truth, not a guess) or the figure fell by more
    /// than a refresh could explain.
    public static func isReset(from previous: TimelineSample, to current: TimelineSample) -> Bool {
        if let before = previous.resetsAt, let after = current.resetsAt,
           after.timeIntervalSince(before) > resetDateTolerance {
            return true
        }
        return current.usedPct < previous.usedPct - resetDropThreshold
    }

    /// Indices of the samples that start a new window (never 0).
    public static func resetIndices(in samples: [TimelineSample]) -> [Int] {
        guard samples.count > 1 else { return [] }
        return (1..<samples.count).filter { isReset(from: samples[$0 - 1], to: samples[$0]) }
    }

    /// The samples split at each reset, oldest segment first.
    public static func segments(_ samples: [TimelineSample]) -> [[TimelineSample]] {
        guard !samples.isEmpty else { return [] }
        var result: [[TimelineSample]] = [[samples[0]]]
        for index in 1..<samples.count {
            if isReset(from: samples[index - 1], to: samples[index]) {
                result.append([samples[index]])
            } else {
                result[result.count - 1].append(samples[index])
            }
        }
        return result
    }

    /// Drops samples older than `retention`, and thins those older than
    /// `rawWindow` to one per hour — the hour's highest figure, so a peak
    /// is never flattened away and a reset still shows as the fall into
    /// the next hour. Everything within `rawWindow` is kept as recorded.
    public static func compacted(
        _ samples: [TimelineSample],
        now: Date,
        rawWindow: TimeInterval,
        retention: TimeInterval
    ) -> [TimelineSample] {
        let oldest = now.addingTimeInterval(-retention)
        let rawCutoff = now.addingTimeInterval(-rawWindow)
        var hourly: [Int: TimelineSample] = [:]
        var raw: [TimelineSample] = []
        for sample in samples where sample.timestamp >= oldest {
            if sample.timestamp >= rawCutoff {
                raw.append(sample)
            } else {
                let bucket = Int(sample.timestamp.timeIntervalSince1970 / 3600)
                if let kept = hourly[bucket], kept.usedPct > sample.usedPct { continue }
                hourly[bucket] = sample
            }
        }
        return hourly.values.sorted { $0.timestamp < $1.timestamp } + raw.sorted { $0.timestamp < $1.timestamp }
    }
}
