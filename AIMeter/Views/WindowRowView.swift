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

    var body: some View {
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

            if showsReset, let resetsAt = window?.resetsAt {
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
    let snapshot: UsageSnapshot?

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
                    moneySubtitle: prefs.creditsAmountSubtitle(for: slot.kind, snapshot: snapshot)
                )
            }
        }
    }
}
