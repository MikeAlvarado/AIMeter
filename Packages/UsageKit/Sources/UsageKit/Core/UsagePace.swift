import Foundation

/// Where a window's usage stands relative to a steady linear burn that
/// would exhaust it exactly at reset — the basis for the bar's pace marker
/// and the on/ahead/behind status. A pure value derived from a single
/// snapshot; no usage history is required.
///
/// (Run-out *prediction* — "at this rate you'll hit the limit in ~2h" —
/// needs a history of samples to estimate the actual burn rate, and is a
/// separate future addition. This type only compares where you are against
/// where a steady burn would put you.)
public struct UsagePace: Equatable, Sendable {
    /// 0–100: where a steady burn to the reset boundary would put usage
    /// right now — i.e. the position of the marker on the bar.
    public let expectedPct: Double
    public let status: Status

    public enum Status: Equatable, Sendable {
        /// Usage tracks the steady line within tolerance.
        case onPace
        /// Used more than the steady line by now — burning fast, at risk
        /// of exhausting the window before it resets.
        case ahead
        /// Used less than the steady line — headroom to spare.
        case behind
    }

    public init(expectedPct: Double, status: Status) {
        self.expectedPct = expectedPct
        self.status = status
    }
}

public enum PaceCalculator {
    /// Tolerance band, in percentage points, around the expected line
    /// within which usage counts as "on pace". Keeps small, expected
    /// fluctuations from flipping the status back and forth.
    public static let defaultTolerance: Double = 5

    /// Pace for a window, or nil when it can't be computed — no reset date
    /// (an idle session, or the credits pseudo-window) or a kind with no
    /// known duration. `now` is injectable for testing.
    public static func pace(
        for window: UsageWindow,
        now: Date = Date(),
        tolerance: Double = defaultTolerance
    ) -> UsagePace? {
        guard let resetsAt = window.resetsAt,
              let duration = window.kind.windowDuration,
              duration > 0 else { return nil }

        let windowStart = resetsAt.addingTimeInterval(-duration)
        let elapsed = now.timeIntervalSince(windowStart)
        let fraction = min(max(elapsed / duration, 0), 1)
        let expectedPct = fraction * 100

        let delta = window.usedPct - expectedPct
        let status: UsagePace.Status
        if delta > tolerance {
            status = .ahead
        } else if delta < -tolerance {
            status = .behind
        } else {
            status = .onPace
        }

        return UsagePace(expectedPct: expectedPct, status: status)
    }
}
