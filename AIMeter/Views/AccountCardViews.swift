import SwiftUI
import UsageKit

/// An account card's protagonist (`AccountCardLayout.hero`): its title, its
/// figure large with "used" or "left" beside it, and on the trailing side
/// its 24-hour trace over when it resets; under them all, a thicker lit bar.
/// One VoiceOver element, like every usage row.
struct HeroWindowView: View {
    @Environment(PreferencesModel.self) private var prefs
    let kind: UsageWindow.Kind
    let window: UsageWindow?
    /// "$14.27 of $25.00" in place of the reset line when the protagonist
    /// is the Credits row (`Preferences.showCreditsAmount`).
    var moneySubtitle: String? = nil
    /// The window's last 24 hours, shown once it holds enough points
    /// (`HistoryChartData.showsSparkline`).
    var sparkline: HistoryChartData? = nil
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 54

    var body: some View {
        let tint = window?.tint(usageColors: prefs.usageColors) ?? Theme.accent
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(window?.title ?? kind.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                    figure
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    if let sparkline, sparkline.showsSparkline {
                        Sparkline(data: sparkline, tint: tint, size: CGSize(width: 92, height: 30))
                    }
                    trailingLine
                }
                .padding(.bottom, 6)
            }
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: tint,
                height: 10,
                lit: true
            )
        }
        .accessibilityElement(children: .combine)
    }

    private var figure: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if let window {
                Text(verbatim: "\(Int(window.displayedPct(prefs.displayMode)))")
                    .font(Theme.figure(size: figureSize))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text(verbatim: "%")
                    .font(Theme.figure(size: figureSize * 0.46))
                    .foregroundStyle(Theme.inkSecondary)
                Text(prefs.displayMode.suffix)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.leading, 4)
            } else {
                Text(verbatim: "--")
                    .font(Theme.figure(size: figureSize))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private var trailingLine: some View {
        if let resetsAt = window?.resetsAt {
            Button {
                prefs.toggleResetStyle()
            } label: {
                Text(UsageFormatting.resetLabel(for: resetsAt, style: prefs.resetStyle))
                    .font(Theme.caption.weight(.medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if let moneySubtitle {
            Text(moneySubtitle)
                .font(Theme.caption.weight(.medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
        }
    }
}

/// The card's other windows, one line each: title, a thin bar, the figure
/// and when it resets (the bare value; "Resets in …" is said by the
/// protagonist and in VoiceOver). Columns are shared, so the bars start
/// and end together.
struct CompactWindowRows: View {
    @Environment(PreferencesModel.self) private var prefs
    let slots: [AccountCardLayout.Slot]
    let snapshot: UsageSnapshot?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 13) {
            ForEach(slots, id: \.kind) { slot in
                row(slot)
            }
        }
    }

    private func row(_ slot: AccountCardLayout.Slot) -> some View {
        let window = slot.window
        let title = window?.title ?? slot.kind.displayName
        let percent = window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "--"
        let trailing = trailingText(slot)
        return GridRow {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                // The title is what the row is; the bar gives way first.
                .layoutPriority(1)
                // The row speaks once, from its first cell.
                .accessibilityLabel(Text(verbatim: [title, percent, window?.resetsAt.map { UsageFormatting.resetLabel(for: $0, style: prefs.resetStyle) }].compactMap { $0 }.joined(separator: ", ")))
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                height: 5
            )
            .frame(minWidth: 36)
            Text(verbatim: percent)
                .font(Theme.compactPercent)
                .foregroundStyle(window == nil ? Theme.inkSecondary : Theme.ink)
                .gridColumnAlignment(.trailing)
                .accessibilityHidden(true)
            trailingCell(trailing, toggles: window?.resetsAt != nil)
                .gridColumnAlignment(.trailing)
                .accessibilityHidden(true)
        }
    }

    /// A reset toggles the style on a tap, like every reset line; a credits
    /// amount is only text.
    @ViewBuilder
    private func trailingCell(_ text: String?, toggles: Bool) -> some View {
        let label = Text(verbatim: text ?? "")
            .font(Theme.caption)
            .foregroundStyle(Theme.inkSecondary)
            .lineLimit(1)
        if toggles {
            Button {
                prefs.toggleResetStyle()
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    private func trailingText(_ slot: AccountCardLayout.Slot) -> String? {
        if let resetsAt = slot.window?.resetsAt {
            return UsageFormatting.resetValue(for: resetsAt, style: prefs.resetStyle, now: Date())
        }
        return prefs.creditsAmountSubtitle(for: slot.kind, snapshot: snapshot)
    }
}
