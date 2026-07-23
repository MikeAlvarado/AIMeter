import SwiftUI
import UsageKit

/// One usage window row: title, percentage, bar, and reset line. Renders a
/// fixed slot — a missing window shows an em dash and an empty track so the
/// three Claude windows are always visible. Tapping the reset line toggles
/// relative/absolute timers globally.
struct WindowRowView: View {
    @Environment(PreferencesModel.self) private var prefs
    let kind: UsageWindow.Kind
    let window: UsageWindow?
    var showsReset = true
    /// "$14.27 of $25.00" — Credits has no reset date, so this optionally
    /// fills the same line instead (`Preferences.showCreditsAmount`).
    var moneySubtitle: String? = nil
    /// Whether to render the pace status caption in this row. Off by
    /// default and enabled only on the Claude detail screen (the dashboard,
    /// menu bar, and landscape intentionally omit it); the caller folds the
    /// warm-up gate into this flag too, so it's already both "this surface
    /// wants pace" and "pace has warmed up".
    var showsPace = false

    var body: some View {
        // Pace is per-window (unlike the grouped reset line): each window
        // has its own used% against the same expected line.
        let pace = showsPace ? window.flatMap { PaceCalculator.pace(for: $0) } : nil
        let showsResetLine = showsReset && window?.resetsAt != nil

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.displayName)
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(percentText)
                    .font(Theme.percent)
                    .foregroundStyle(Theme.ink)
            }

            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint ?? Theme.accent
            )

            if pace != nil || showsResetLine || moneySubtitle != nil {
                HStack(spacing: 6) {
                    if let pace {
                        Text(pace.status.label)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    if showsResetLine, let resetsAt = window?.resetsAt {
                        Button {
                            prefs.toggleResetStyle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.trianglehead.clockwise")
                                Text(UsageFormatting.resetLabel(for: resetsAt, style: prefs.resetStyle))
                            }
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSecondary)
                        }
                        .buttonStyle(.plain)
                    } else if let moneySubtitle {
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle")
                            Text(moneySubtitle)
                        }
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        // One VoiceOver element per row: "5-hour session, 45%, Resets in…".
        .accessibilityElement(children: .combine)
    }

    private var percentText: String {
        window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "—"
    }
}

/// The three fixed window rows separated by hairlines — shared between the
/// dashboard card and the provider detail card.
struct WindowRowsList: View {
    @Environment(PreferencesModel.self) private var prefs
    @Environment(UsageModel.self) private var model
    let snapshot: UsageSnapshot?
    /// Only the Claude detail screen passes `true`; the dashboard, menu
    /// bar, and landscape leave it off so pace stays out of the glance.
    var showsPace = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            let slots = WindowSlots(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback).slots
            ForEach(Array(slots.enumerated()), id: \.element.kind) { index, slot in
                if index > 0 {
                    Divider().overlay(Theme.track)
                }
                WindowRowView(
                    kind: slot.kind,
                    window: slot.window,
                    showsReset: WindowSlots.showsReset(at: index, in: slots),
                    moneySubtitle: prefs.creditsAmountSubtitle(for: slot.kind, snapshot: snapshot),
                    showsPace: showsPace && model.paceReady
                )
            }
        }
    }
}
