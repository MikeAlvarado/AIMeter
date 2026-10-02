import Foundation
import UsageKit

/// The three spans the History card offers.
enum HistoryRange: CaseIterable {
    case day, week, month

    var interval: TimeInterval {
        switch self {
        case .day: 24 * 3600
        case .week: 7 * 24 * 3600
        case .month: 30 * 24 * 3600
        }
    }

    /// Pill label.
    var label: String {
        switch self {
        case .day: String(localized: "24 h")
        case .week: String(localized: "7 days")
        case .month: String(localized: "30 days")
        }
    }

    /// For the spoken summary: "the last 24 hours".
    var spokenSpan: String {
        switch self {
        case .day: String(localized: "the last 24 hours")
        case .week: String(localized: "the last 7 days")
        case .month: String(localized: "the last 30 days")
        }
    }

    /// X-axis tick text for a date in this span.
    func axisLabel(_ date: Date) -> String {
        switch self {
        case .day: date.formatted(.dateTime.hour())
        case .week: date.formatted(.dateTime.weekday(.abbreviated))
        case .month: date.formatted(.dateTime.day().month(.abbreviated))
        }
    }
}

/// What the History chart and the row sparkline draw, shaped once from the
/// stored samples: points tagged with the window they belong to (so the
/// line breaks at a reset instead of drawing a cliff), the reset instants
/// for the dashed rules, the peak, and whether there is enough history to
/// show a curve at all. Pure, so these rules are tested rather than
/// eyeballed.
struct HistoryChartData: Equatable {
    struct Point: Identifiable, Equatable {
        let id: Int
        let date: Date
        let usedPct: Double
        /// Index of the window this sample belongs to, counted from the
        /// oldest in range — the chart's series key.
        let segment: Int
    }

    /// Below this the "recording" state shows instead of a curve: a chart
    /// of one or two points asserts a shape it doesn't have.
    static let minimumSamples = 2
    static let minimumSpan: TimeInterval = 3600
    /// The dashed guide line, the dashboard's own red threshold.
    static let dangerLine: Double = 80
    /// Reset rules are drawn only up to this many in range — beyond it
    /// they hatch the chart instead of marking anything.
    static let maxResetRules = 12

    let range: HistoryRange
    let start: Date
    let end: Date
    let points: [Point]
    let resets: [Date]
    let peak: Point?
    let isReady: Bool
    /// The oldest sample on record for this window (not just in range),
    /// for the "Recording since …" state.
    let recordingSince: Date?

    init(samples: [TimelineSample], range: HistoryRange, now: Date = Date()) {
        let start = now.addingTimeInterval(-range.interval)
        self.range = range
        self.start = start
        end = now
        recordingSince = samples.first?.timestamp
        let inRange = samples.filter { $0.timestamp >= start && $0.timestamp <= now }
        var built: [Point] = []
        var resets: [Date] = []
        for (segment, window) in UsageTimeline.segments(inRange).enumerated() {
            if segment > 0, let first = window.first { resets.append(first.timestamp) }
            for sample in window {
                built.append(Point(id: built.count, date: sample.timestamp, usedPct: sample.usedPct, segment: segment))
            }
        }
        points = built
        self.resets = resets
        peak = built.max { $0.usedPct < $1.usedPct }
        if let first = inRange.first, let last = inRange.last {
            isReady = inRange.count >= Self.minimumSamples && last.timestamp.timeIntervalSince(first.timestamp) >= Self.minimumSpan
        } else {
            isReady = false
        }
    }

    /// Enough to draw a sparkline worth looking at.
    var showsSparkline: Bool { isReady && points.count >= 3 }

    /// One sentence for VoiceOver — the chart is a single element.
    func summary(for kind: UsageWindow.Kind) -> String {
        var text = String(localized: "\(kind.displayName) usage over \(range.spokenSpan).")
        if let peak {
            let when = peak.date.formatted(date: range == .day ? .omitted : .abbreviated, time: .shortened)
            text += " " + String(localized: "Peaked at \(Int(peak.usedPct))% at \(when).")
        }
        switch resets.count {
        case 0: text += " " + String(localized: "No resets.")
        case 1: text += " " + String(localized: "Reset once.")
        default: text += " " + String(localized: "Reset \(resets.count) times.")
        }
        return text
    }
}
