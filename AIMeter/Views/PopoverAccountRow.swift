#if os(macOS)
import SwiftUI
import UsageKit

/// The popover's measures.
enum PopoverTableMetrics {
    static let popoverWidth: CGFloat = 400
    /// The protagonist's share of a card's width; the other windows take
    /// the rest.
    static let heroWidth: CGFloat = 124
    static let heroSpacing: CGFloat = 16
    /// The other windows' fixed columns, the same in every card, so the
    /// bars, figures and resets of every account line up down the popover
    /// (the iPhone's flexible grid sized each card's on its own).
    static let titleColumn: CGFloat = 56
    static let percentColumn: CGFloat = 34
    static let resetColumn: CGFloat = 46
    static let columnGap: CGFloat = 8
}

/// One account in the menu bar popover (4.0.1): the iPhone's account card
/// at the popover's size (Mike, 2026-10-21: "like the new iPhone"). Its
/// identity on top (mark, name, plan pill), then the protagonist
/// (`AccountCardLayout.hero`, the window closest to its limit) large on the
/// left and the others on the right, one line each, the iPhone's own
/// `CompactWindowRows`. A card of its own on the popover's background, so
/// each account reads as one group; the card under the pointer darkens a
/// little, and a click opens the account's detail in the Dashboard window
/// (`AppChrome.openAccount`). Its status tail is the card's: errors, "Sign
/// in again" (routed to the Dashboard, since the popover presents no
/// sheets), the incident line, and "Updated" only once stale.
struct PopoverAccountRow: View {
    let usage: UsageModel.AccountUsage
    @Environment(PreferencesModel.self) private var prefs
    @Environment(UsageModel.self) private var model
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Reached with Tab (Full Keyboard Access): it lights like the
    /// pointer's card, and Return or Space opens it.
    @FocusState private var focused: Bool

    var body: some View {
        let layout = AccountCardLayout(snapshot: usage.snapshot, modelSlotFallback: prefs.modelSlotFallback)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProviderIdentityView(
                    name: usage.account.displayName,
                    iconSize: 20,
                    iconCornerRadius: 6,
                    font: .subheadline.weight(.semibold),
                    nameColor: Theme.ink,
                    planName: usage.snapshot?.planName,
                    icon: usage.account.icon,
                    compactPill: true
                )
                Spacer(minLength: 0)
            }
            // The others start on the protagonist's title line, so the
            // card reads as one table rather than a block with a list
            // floating beside it.
            HStack(alignment: .firstTextBaseline, spacing: PopoverTableMetrics.heroSpacing) {
                PopoverHeroView(slot: layout.hero, snapshot: usage.snapshot)
                    .frame(width: layout.others.isEmpty ? nil : PopoverTableMetrics.heroWidth, alignment: .leading)
                    .frame(maxWidth: layout.others.isEmpty ? .infinity : nil, alignment: .leading)
                if !layout.others.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(layout.others, id: \.kind) { slot in
                            PopoverCompactRow(slot: slot, snapshot: usage.snapshot)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            UsageStatusFooter(
                snapshot: usage.snapshot,
                error: usage.lastError,
                reauthenticate: usage.needsReauthentication ? { AppChrome.connect(.reconnect(usage.account)) } : nil,
                offline: usage.isOffline,
                serviceIncident: model.incidentNote(for: usage),
                updated: .whenStale
            )
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.ink.opacity(hovering || focused ? 0.05 : 0))
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { hovering = inside }
        }
        .onTapGesture {
            AppChrome.openAccount(usage.account.accountID)
        }
        .focusable(interactions: .activate)
        .focused($focused)
        .onKeyPress(keys: [.return, .space]) { _ in
            AppChrome.openAccount(usage.account.accountID)
            return .handled
        }
        .help(Text("Open \(usage.account.displayName) in AIMeter"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            AppChrome.openAccount(usage.account.accountID)
        }
    }
}

/// A popover card's protagonist: `HeroWindowView` at the popover's size,
/// its title, the figure with "%" and "used" or "left", the lit bar, and
/// when it resets under them (there is no room beside the figure).
private struct PopoverHeroView: View {
    @Environment(PreferencesModel.self) private var prefs
    let slot: AccountCardLayout.Slot
    let snapshot: UsageSnapshot?

    var body: some View {
        let window = slot.window
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                // The short name, as the rows beside it say theirs.
                Text(window?.shortTitle ?? slot.kind.shortName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if let window {
                        Text(verbatim: "\(Int(window.displayedPct(prefs.displayMode)))")
                            .font(Theme.figure(size: 30))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                        Text(verbatim: "%")
                            .font(Theme.figure(size: 14))
                            .foregroundStyle(Theme.inkSecondary)
                        Text(prefs.displayMode.suffix)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.leading, 3)
                    } else {
                        Text(verbatim: "--")
                            .font(Theme.figure(size: 30))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .lineLimit(1)
            }
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                height: 6,
                lit: true
            )
            if let line = resetLine {
                Text(verbatim: line)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var resetLine: String? {
        if let resetsAt = slot.window?.resetsAt {
            return UsageFormatting.resetLabel(for: resetsAt, style: prefs.resetStyle)
        }
        return prefs.creditsAmountSubtitle(for: slot.kind, snapshot: snapshot)
    }
}
/// One of a popover card's other windows: the Dashboard card's compact
/// row (`CompactWindowRows`: name, a 5 pt bar, figure, bare reset) on
/// fixed columns, the same in every card.
private struct PopoverCompactRow: View {
    @Environment(PreferencesModel.self) private var prefs
    let slot: AccountCardLayout.Slot
    let snapshot: UsageSnapshot?

    var body: some View {
        let window = slot.window
        let title = window?.shortTitle ?? slot.kind.shortName
        let percent = window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "--"
        HStack(alignment: .firstTextBaseline, spacing: PopoverTableMetrics.columnGap) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: PopoverTableMetrics.titleColumn, alignment: .leading)
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                height: 5
            )
            .frame(height: 5)
            // On the text's middle, not its baseline.
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(verbatim: percent)
                .font(Theme.compactPercent)
                .foregroundStyle(window == nil ? Theme.inkSecondary : Theme.ink)
                .frame(width: PopoverTableMetrics.percentColumn, alignment: .trailing)
            Text(verbatim: trailing ?? "")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: PopoverTableMetrics.resetColumn, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [
            window?.title ?? slot.kind.displayName,
            percent,
            window?.resetsAt.map { UsageFormatting.resetLabel(for: $0, style: prefs.resetStyle) },
        ].compactMap { $0 }.joined(separator: ", ")))
    }

    private var trailing: String? {
        if let resetsAt = slot.window?.resetsAt {
            return UsageFormatting.resetValue(for: resetsAt, style: prefs.resetStyle, now: Date())
        }
        return prefs.creditsAmountSubtitle(for: slot.kind, snapshot: snapshot)
    }
}
#endif
