#if os(macOS)
import SwiftUI
import UsageKit

/// One account in the menu bar popover (4.0): its identity and when it last
/// refreshed on one line, then its windows side by side in columns (the
/// short name, the figure, a thin bar, when it resets), the way the notch
/// island lines them up, so four accounts fit without scrolling. The block
/// under the pointer lights up, and a click opens the account's detail in
/// the Dashboard window (`AppChrome.openAccount`). Its status tail is the
/// card's: errors, "Sign in again" (routed to the Dashboard, since the
/// popover presents no sheets), the incident line, and "Updated" only once
/// stale.
struct PopoverAccountBlock: View {
    let usage: UsageModel.AccountUsage
    @Environment(PreferencesModel.self) private var prefs
    @Environment(UsageModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let slots = WindowSlots(snapshot: usage.snapshot, modelSlotFallback: prefs.modelSlotFallback).slots
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProviderIdentityView(
                    name: usage.account.displayName,
                    iconSize: 18,
                    iconCornerRadius: 5,
                    font: .subheadline.weight(.semibold),
                    nameColor: Theme.ink,
                    planName: usage.snapshot?.planName,
                    icon: usage.account.icon,
                    compactPill: true
                )
                Spacer(minLength: 6)
                if hovering {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .transition(.opacity)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(slots, id: \.kind) { slot in
                    PopoverWindowColumn(kind: slot.kind, window: slot.window, snapshot: usage.snapshot)
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
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.ink.opacity(hovering ? 0.07 : 0))
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
        }
        .onTapGesture {
            AppChrome.openAccount(usage.account.accountID)
        }
        .help(Text("Open \(usage.account.displayName) in AIMeter"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            AppChrome.openAccount(usage.account.accountID)
        }
    }
}

/// One window in a popover block: its short name, the figure, a thin bar,
/// and its bare reset (or a credits amount).
private struct PopoverWindowColumn: View {
    @Environment(PreferencesModel.self) private var prefs
    let kind: UsageWindow.Kind
    let window: UsageWindow?
    let snapshot: UsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(window?.shortTitle ?? kind.shortName)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            Text(verbatim: window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "--")
                .font(Theme.figure(size: 19))
                .foregroundStyle(window == nil ? Theme.inkSecondary : Theme.ink)
                .contentTransition(.numericText())
            UsageBarView(
                value: window?.displayedPct(prefs.displayMode),
                tint: window?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                height: 4
            )
            Text(verbatim: trailing ?? " ")
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [
            window?.title ?? kind.displayName,
            window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "--",
            window?.resetsAt.map { UsageFormatting.resetLabel(for: $0, style: prefs.resetStyle) },
        ].compactMap { $0 }.joined(separator: ", ")))
    }

    private var trailing: String? {
        if let resetsAt = window?.resetsAt {
            return UsageFormatting.resetValue(for: resetsAt, style: prefs.resetStyle, now: Date())
        }
        return prefs.creditsAmountSubtitle(for: kind, snapshot: snapshot)
    }
}
#endif
