import Foundation

/// One recorded observation of a window's usage at a point in time — the
/// unit stored by `UsageHistoryStore` and fed to the recent-rate predictor.
public struct UsageSample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let usedPct: Double

    public init(timestamp: Date, usedPct: Double) {
        self.timestamp = timestamp
        self.usedPct = usedPct
    }
}

/// A projection of when a window's usage reaches 100%, relative to when it
/// actually resets. Whether it "runs out early" is the core of the run-out
/// prediction.
public struct RunOutProjection: Equatable, Sendable {
    /// Projected moment usage hits 100% at the estimated burn rate.
    public let projectedExhaustion: Date
    /// The window's own reset boundary, for comparison.
    public let resetsAt: Date

    public init(projectedExhaustion: Date, resetsAt: Date) {
        self.projectedExhaustion = projectedExhaustion
        self.resetsAt = resetsAt
    }

    /// True when usage is projected to hit 100% before the window resets.
    public var runsOutEarly: Bool { projectedExhaustion < resetsAt }

    /// How long before the reset it's projected to run out (0 when it isn't
    /// projected to run out early).
    public var earlyBy: TimeInterval {
        max(0, resetsAt.timeIntervalSince(projectedExhaustion))
    }
}

/// Two run-out estimators, per the "hybrid" model:
/// - `averageProjection` uses the *average* rate since the window began —
///   stable, works from a single snapshot with no history, so it drives the
///   number shown on screen.
/// - `recentProjection` uses the *recent* rate over the last samples —
///   reactive to a sudden burst, so it drives the run-out alert (which
///   should fire early rather than wait for the average to catch up).
public enum RunOutPredictor {
    /// Minimum used% below which a projection is suppressed as too noisy to
    /// be worth showing or alerting on early in a window.
    public static let alertMinimumUsedPct: Double = 20

    // MARK: Average (display)

    /// Projection from the average burn rate since the window started.
    /// `now` and `minimumUsedPct` are injectable for testing.
    public static func averageProjection(
        for window: UsageWindow,
        now: Date = Date(),
        minimumUsedPct: Double = 0
    ) -> RunOutProjection? {
        guard let resetsAt = window.resetsAt,
              let duration = window.kind.windowDuration, duration > 0 else { return nil }
        let windowStart = resetsAt.addingTimeInterval(-duration)
        let elapsed = now.timeIntervalSince(windowStart)
        guard elapsed > 0, window.usedPct > minimumUsedPct, window.usedPct < 100 else { return nil }

        // avgRate = usedPct / elapsed → time to 100% = (100 − used) / avgRate.
        let remaining = (100 - window.usedPct) * elapsed / window.usedPct
        return RunOutProjection(
            projectedExhaustion: now.addingTimeInterval(remaining),
            resetsAt: resetsAt
        )
    }

    /// Average projections for every window in a snapshot, keyed by kind —
    /// convenience for the forecast UI and for immediate alert scheduling
    /// before any history exists.
    public static func averageProjections(
        for snapshot: UsageSnapshot,
        now: Date = Date(),
        minimumUsedPct: Double = 0
    ) -> [UsageWindow.Kind: RunOutProjection] {
        var result: [UsageWindow.Kind: RunOutProjection] = [:]
        for window in snapshot.windows {
            if let projection = averageProjection(for: window, now: now, minimumUsedPct: minimumUsedPct) {
                result[window.kind] = projection
            }
        }
        return result
    }

    // MARK: Recent (alerts)

    /// Projection from the recent burn rate — the slope of used% over the
    /// samples within `recentSpan` (falling back to the last two samples).
    /// nil when there isn't enough recent signal, usage is under
    /// `minimumUsedPct`, or the recent trend isn't rising.
    public static func recentProjection(
        for window: UsageWindow,
        samples: [UsageSample],
        now: Date = Date(),
        recentSpan: TimeInterval = 90 * 60,
        minimumUsedPct: Double = alertMinimumUsedPct
    ) -> RunOutProjection? {
        guard let resetsAt = window.resetsAt,
              window.usedPct >= minimumUsedPct, window.usedPct < 100 else { return nil }

        let cutoff = now.addingTimeInterval(-recentSpan)
        var recent = samples.filter { $0.timestamp >= cutoff }
        if recent.count < 2 {
            recent = Array(samples.suffix(2))
        }
        guard recent.count >= 2, let rate = slope(of: recent), rate > 0 else { return nil }

        let remaining = (100 - window.usedPct) / rate
        guard remaining.isFinite, remaining >= 0 else { return nil }
        return RunOutProjection(
            projectedExhaustion: now.addingTimeInterval(remaining),
            resetsAt: resetsAt
        )
    }

    /// Least-squares slope of used% against time, in percentage points per
    /// second. nil when the timestamps don't vary.
    static func slope(of samples: [UsageSample]) -> Double? {
        guard samples.count >= 2 else { return nil }
        let t0 = samples[0].timestamp.timeIntervalSinceReferenceDate
        let xs = samples.map { $0.timestamp.timeIntervalSinceReferenceDate - t0 }
        let ys = samples.map(\.usedPct)
        let n = Double(samples.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for i in samples.indices {
            let dx = xs[i] - meanX
            num += dx * (ys[i] - meanY)
            den += dx * dx
        }
        guard den > 0 else { return nil }
        return num / den
    }
}

/// Detects a window crossing a usage threshold upward between two
/// snapshots — the basis for both the configurable "near-limit" warning
/// and the "limit reached" alert (which is just the same crossing at
/// ~100%). Pure so it's testable; the app decides whether to notify.
public enum ThresholdDetector {
    /// Used% at or above which a window counts as maxed out.
    public static let limitReachedThreshold: Double = 99.5

    /// Kinds whose used% rose from below `threshold` to at or above it
    /// between the two snapshots — a single upward crossing, so it fires
    /// once rather than on every refresh while above. A window with no
    /// counterpart in `previous` isn't flagged (no baseline → don't alert
    /// on first sight, e.g. connecting while already high).
    public static func crossedUp(
        previous: UsageSnapshot,
        current: UsageSnapshot,
        threshold: Double
    ) -> [UsageWindow.Kind] {
        var kinds: [UsageWindow.Kind] = []
        for cur in current.windows {
            guard let prev = previous.windows.first(where: { $0.kind == cur.kind }),
                  prev.usedPct < threshold, cur.usedPct >= threshold else { continue }
            kinds.append(cur.kind)
        }
        return kinds
    }
}

/// Detects a window that reset *before* its scheduled boundary — an early
/// refill — by comparing consecutive snapshots. Pure so it's testable; the
/// app decides whether to notify.
public enum ResetDetector {
    /// Kinds whose used% dropped by at least `dropThreshold` between two
    /// snapshots, where the drop happened at least `margin` before the
    /// previously-known reset time (so a normal on-schedule reset isn't
    /// flagged).
    public static func earlyResets(
        previous: UsageSnapshot,
        current: UsageSnapshot,
        now: Date = Date(),
        dropThreshold: Double = 10,
        margin: TimeInterval = 10 * 60
    ) -> [UsageWindow.Kind] {
        var kinds: [UsageWindow.Kind] = []
        for cur in current.windows {
            guard let prev = previous.windows.first(where: { $0.kind == cur.kind }),
                  let prevReset = prev.resetsAt,
                  cur.usedPct <= prev.usedPct - dropThreshold,
                  now < prevReset.addingTimeInterval(-margin) else { continue }
            kinds.append(cur.kind)
        }
        return kinds
    }
}
