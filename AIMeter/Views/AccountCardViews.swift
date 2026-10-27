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
    /// A card in two columns: the figure at 46 pt instead of 54, so it
    /// and the reset line fit side by side at full size. Left to
    /// `minimumScaleFactor`, the two cards of a row drew their figures at
    /// two sizes ("73" smaller than "61") and cut "Resets in 1h…".
    var narrow = false
    @ScaledMetric(relativeTo: .largeTitle) private var baseFigureSize: CGFloat = 54

    private var figureSize: CGFloat { narrow ? baseFigureSize * 46 / 54 : baseFigureSize }

    var body: some View {
        let tint = window?.tint(usageColors: prefs.usageColors) ?? Theme.accent
        VStack(alignment: .leading, spacing: 14) {
            // Side by side when the figure and the reset line fit at full
            // size; stacked otherwise (German or French words, a larger
            // text size, a narrow column). 4.3.0 kept them side by side at
            // any cost and the card ran past the screen's edges.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 12) {
                    titleAndFigure
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 8) {
                        sparklineView(tint)
                        trailingLine(fixed: true)
                    }
                    .padding(.bottom, 6)
                }
                VStack(alignment: .leading, spacing: 8) {
                    titleAndFigure
                    HStack(alignment: .center, spacing: 12) {
                        trailingLine(fixed: false)
                        Spacer(minLength: 8)
                        sparklineView(tint)
                    }
                }
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

    private var titleAndFigure: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(window?.title ?? kind.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(2)
            figure
        }
    }

    @ViewBuilder
    private func sparklineView(_ tint: Color) -> some View {
        if let sparkline, sparkline.showsSparkline {
            Sparkline(data: sparkline, tint: tint, size: CGSize(width: 92, height: 30))
        }
    }

    private var figure: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
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

    /// When it resets, whole beside the figure (`fixed`, the layout only
    /// chosen when it fits) or wrapping under it.
    @ViewBuilder
    private func trailingLine(fixed: Bool) -> some View {
        if let resetsAt = window?.resetsAt {
            Button {
                prefs.toggleResetStyle()
            } label: {
                Text(UsageFormatting.resetLabel(for: resetsAt, style: prefs.resetStyle))
                    .font(Theme.caption.weight(.medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(fixed ? 1 : 2)
                    .fixedSize(horizontal: fixed, vertical: !fixed)
                    .tapTarget()
            }
            .buttonStyle(.plain)
        } else if let moneySubtitle {
            Text(moneySubtitle)
                .font(Theme.caption.weight(.medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(fixed ? 1 : 2)
                .fixedSize(horizontal: fixed, vertical: !fixed)
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
        // One line a window in shared columns when the longest title fits
        // whole; otherwise each window on two lines, its title over its
        // bar, figure and reset (German or French titles, a larger text
        // size), rather than a row wider than the card.
        ViewThatFits(in: .horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 13) {
                ForEach(slots, id: \.kind) { slot in
                    row(slot)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(slots, id: \.kind) { slot in
                    stackedRow(slot)
                }
            }
        }
    }

    private func stackedRow(_ slot: AccountCardLayout.Slot) -> some View {
        let window = slot.window
        return VStack(alignment: .leading, spacing: 5) {
            Text(window?.title ?? slot.kind.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                UsageBarView(
                    value: window?.displayedPct(prefs.displayMode),
                    tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                    height: 5
                )
                Text(verbatim: percentText(window))
                    .font(Theme.compactPercent)
                    .foregroundStyle(window == nil ? Theme.inkSecondary : Theme.ink)
                    .fixedSize()
                trailingCell(trailingText(slot), toggles: window?.resetsAt != nil)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenLabel(slot)))
    }

    private func percentText(_ window: UsageWindow?) -> String {
        window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "--"
    }

    private func spokenLabel(_ slot: AccountCardLayout.Slot) -> String {
        let window = slot.window
        return [window?.title ?? slot.kind.displayName, percentText(window), window?.resetsAt.map { UsageFormatting.resetLabel(for: $0, style: prefs.resetStyle) }]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func row(_ slot: AccountCardLayout.Slot) -> some View {
        let window = slot.window
        let title = window?.title ?? slot.kind.displayName
        let percent = percentText(window)
        let trailing = trailingText(slot)
        return GridRow {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                // The title is what the row is; the bar gives way first,
                // then the title shrinks and, past that, ends in "…".
                .layoutPriority(1)
                // The row speaks once, from its first cell.
                .accessibilityLabel(Text(verbatim: spokenLabel(slot)))
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                height: 5
            )
            .frame(minWidth: 36)
            // The figure and the reset never shorten: in a narrow card
            // (an iPad's or an iPhone Duo's two columns) they read "4…" and
            // "2h…" while a long title kept its room.
            Text(verbatim: percent)
                .font(Theme.compactPercent)
                .foregroundStyle(window == nil ? Theme.inkSecondary : Theme.ink)
                .fixedSize()
                .gridColumnAlignment(.trailing)
                .accessibilityHidden(true)
            trailingCell(trailing, toggles: window?.resetsAt != nil)
                .fixedSize()
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
                label.tapTarget()
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
