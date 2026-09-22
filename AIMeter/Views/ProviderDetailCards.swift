import SwiftUI
import UsageKit

/// Anthropic's documented weekday peak-usage window, computed on-device
/// from a fixed schedule (see `ClaudePeakSchedule`) — there's no server
/// signal to key off instead (`docs/design/peak-hours-investigation.md`).
struct PeakHoursCard: View {
    let status: ClaudePeakStatus

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: status.isPeak ? "bolt.fill" : "bolt.slash")
                    .foregroundStyle(status.isPeak ? Theme.danger : Theme.inkSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title)
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                    Text(status.subtitle)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Per-window run-out forecast from the average pace so far — a warning
/// row for each window projected to hit its limit before it resets, or a
/// single reassuring row when none are. Uses the stable average-rate
/// projection (works from a single snapshot); the recent-rate refinement
/// is what drives the alerts, not this display.
struct ForecastCard: View {
    let snapshot: UsageSnapshot
    /// While false (pace still warming up), the card shows a "learning"
    /// state rather than a forecast — see `UsageModel.paceReady`.
    var ready = true

    var body: some View {
        if ready {
            forecast
        } else {
            learning
        }
    }

    private var learning: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "hourglass")
                    .foregroundStyle(Theme.inkSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Learning your pace…")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                    Text("Insights appear after a couple of sessions to learn from.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var forecast: some View {
        // Gate on the Phase-1 pace status so the forecast and the row's
        // "Ahead of pace" caption never disagree — a window only "runs out
        // early" here when it's genuinely ahead (beyond the pace tolerance),
        // not by a trivial fraction.
        let atRisk: [(UsageWindow.Kind, RunOutProjection)] = snapshot.windows.compactMap { window in
            guard PaceCalculator.pace(for: window)?.status == .ahead,
                  let projection = RunOutPredictor.averageProjection(for: window),
                  projection.runsOutEarly else { return nil }
            return (window.kind, projection)
        }

        return Card {
            if atRisk.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Theme.accent)
                    Text("Every limit is on track to last its window.")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                    ForEach(Array(atRisk.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Divider().overlay(Theme.track)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.0.displayName)
                                .font(Theme.rowTitle)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(runsOutText(item.1))
                                .font(.body)
                                .foregroundStyle(Theme.danger)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }

    private func runsOutText(_ projection: RunOutProjection) -> String {
        let early = UsageFormatting.relativeString(from: projection.projectedExhaustion, to: projection.resetsAt)
        return String(localized: "Runs out ~\(early) early")
    }
}

/// Plain label/value rows with hairline dividers — the raw provider
/// details (Spend, Extra usage) mirroring the reference design.
struct DetailRowsCard: View {
    let rows: [(String, String)]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider().overlay(Theme.track)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0)
                            .font(Theme.rowTitle)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(row.1)
                            .font(.body)
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }
}

/// The label/value rows for the raw provider details — built here rather
/// than in the view so the copy and the placeholder rule stay in one place.
enum ProviderDetailRows {
    static func severityLabel(_ severity: UsageWindow.Severity) -> String {
        switch severity {
        case .normal: String(localized: "Normal")
        case .warning: String(localized: "Warning")
        case .critical: String(localized: "Critical")
        case .exceeded: String(localized: "Exceeded")
        }
    }

    static func spend(_ spend: SpendStatus) -> [(String, String)] {
        var rows = [(String(localized: "Enabled"), yesNo(spend.enabled))]
        if let percent = spend.percent {
            rows.append((String(localized: "Percent"), spend.enabled ? "\(Int(percent))%" : placeholder))
        }
        if let severity = spend.severity {
            rows.append((String(localized: "Severity"), spend.enabled ? severityLabel(severity) : placeholder))
        }
        if let used = spend.usedAmount {
            rows.append((String(localized: "Used"), spend.enabled ? money(used, spend.currency) : placeholder))
        }
        if let limit = spend.limitAmount {
            rows.append((String(localized: "Limit"), spend.enabled ? money(limit, spend.currency) : placeholder))
        }
        return rows
    }

    static func extraUsage(_ extra: ExtraUsageStatus) -> [(String, String)] {
        var rows = [(String(localized: "Enabled"), yesNo(extra.enabled))]
        if let used = extra.usedCredits {
            rows.append((String(localized: "Used credits"), extra.enabled ? money(used, extra.currency) : placeholder))
        }
        if let limit = extra.monthlyLimit {
            rows.append((String(localized: "Monthly limit"), extra.enabled ? money(limit, extra.currency) : placeholder))
        }
        if let utilization = extra.utilization {
            rows.append((String(localized: "Utilization"), extra.enabled ? "\(Int(utilization))%" : placeholder))
        }
        return rows
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? String(localized: "Yes") : String(localized: "No")
    }

    /// Shown instead of a figure when the account has this feature off —
    /// the endpoint still reports stale percent/used/limit values even
    /// then, and this is the same "no live data" placeholder every other
    /// row in the app uses instead of a misleading number.
    private static var placeholder: String { "—" }

    private static func money(_ amount: Double, _ currency: String?) -> String {
        amount.formatted(.currency(code: currency ?? "USD"))
    }
}
