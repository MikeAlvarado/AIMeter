import Charts
import SwiftUI
import UsageKit

/// Provider Detail → History: the % of limit used over time for one of
/// this account's windows, from `UsageTimelineStore` through
/// `UsageModel.timeline(for:kind:)`. Window and span pills on top; until
/// an hour of samples exists the card shows when recording started
/// instead of a curve.
///
/// The line breaks at every reset (one series per window segment) with a
/// dashed rule marking the boundary, and a faint dashed line at 80 % — the
/// same threshold that turns a bar red. One color for the curve, on
/// purpose; the data is "% of limit", never tokens, and the footnote says
/// so.
struct HistoryCard: View {
    @Environment(UsageModel.self) private var model
    let accountID: String
    let snapshot: UsageSnapshot
    @State private var kind: UsageWindow.Kind = .session
    @State private var range: HistoryRange = .day

    var body: some View {
        let data = HistoryChartData(samples: model.timeline(for: accountID, kind: kind), range: range)
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                SegmentedPill(options: kinds.map { ($0, $0.shortName) }, selection: $kind)
                SegmentedPill(options: HistoryRange.allCases.map { ($0, $0.label) }, selection: $range)
                if data.isReady {
                    chart(data)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(data.summary(for: kind))
                } else {
                    recording(data)
                }
            }
        }
        .onAppear {
            if !kinds.contains(kind), let first = kinds.first { kind = first }
        }
    }

    /// The windows this account actually reports — credits is a
    /// synthesized pseudo-window with nothing recorded, so it's not here.
    private var kinds: [UsageWindow.Kind] {
        snapshot.windows.map(\.kind)
    }

    private func chart(_ data: HistoryChartData) -> some View {
        Chart {
            ForEach(data.points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Used", point.usedPct),
                    series: .value("Window", point.segment)
                )
                .foregroundStyle(
                    LinearGradient(colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Used", point.usedPct),
                    series: .value("Window", point.segment)
                )
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
            }
            // Past a dozen resets in range (a week of 5-hour sessions is
            // ~33) the rules would hatch the whole chart; the sawtooth
            // itself shows the resets then.
            if data.resets.count <= HistoryChartData.maxResetRules {
                ForEach(data.resets, id: \.self) { reset in
                    RuleMark(x: .value("Reset", reset))
                        .foregroundStyle(Theme.inkSecondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            RuleMark(y: .value("Threshold", HistoryChartData.dangerLine))
                .foregroundStyle(Theme.danger.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
        }
        .chartXScale(domain: data.start...data.end)
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text(verbatim: "\(percent)%")
                            .font(.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(data.range.axisLabel(date))
                            .font(.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        .frame(height: 150)
    }

    private func recording(_ data: HistoryChartData) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(Theme.inkSecondary)
            VStack(alignment: .leading, spacing: 2) {
                if let since = data.recordingSince {
                    Text("Recording since \(since.formatted(date: .abbreviated, time: .shortened))")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                } else {
                    Text("Recording starts with the next refresh")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                Text("The chart appears once an hour of samples exists in this range.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
    }
}

/// The Dashboard row's 24-hour trace: the same points, no axes, no
/// interaction, in the secondary color so it reads as texture rather than
/// a second figure. Unlike the card's chart it is drawn as **one**
/// continuous line with a faint fill, not one segment per window: at
/// 56×16 pt a session's five-hour sawtooth split at every reset came out
/// as a row of hatch marks, while a connected waveform still reads as
/// "rose, reset, rose". Decorative — the row already speaks its value.
struct Sparkline: View {
    let data: HistoryChartData

    var body: some View {
        Chart(data.points) { point in
            AreaMark(x: .value("Time", point.date), y: .value("Used", point.usedPct))
                .foregroundStyle(Theme.inkSecondary.opacity(0.14))
                .interpolationMethod(.linear)
            LineMark(x: .value("Time", point.date), y: .value("Used", point.usedPct))
                .foregroundStyle(Theme.inkSecondary.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, lineJoin: .round))
                .interpolationMethod(.linear)
        }
        .chartXScale(domain: data.start...data.end)
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(width: 56, height: 16)
        .accessibilityHidden(true)
    }
}
