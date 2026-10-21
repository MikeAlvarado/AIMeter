import SwiftUI
import WidgetKit
import UsageKit

/// The all-accounts widget's condensed layout (Edit Widget → Layout), as
/// picked on 2026-10-21 from three drawings (variant C): six accounts, one
/// line each with the account's protagonist (the window
/// `AccountCardLayout` puts first, as the cards do: its thick bar and its
/// figure), and under the name every window with its figure in small
/// text, the protagonist first ("Week 61% · Session 42% · Top model
/// 18%"). Then the soonest session reset of them all as a live
/// countdown. What a line gives up for the room is each window's reset
/// and the iOS refresh button.
struct CondensedAccountsView: View {
    let entry: AllAccountsEntry
    static let maxRows = 6
    private static let nameWidth: CGFloat = 58
    private static let figureWidth: CGFloat = 40

    var body: some View {
        let rows = Array(entry.rows.prefix(Self.maxRows))
        VStack(alignment: .leading, spacing: 0) {
            header
            if entry.rows.isEmpty {
                Text("Open AIMeter to load usage")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 10)
                // The lines share the height, the room left over between
                // them.
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Spacer(minLength: 8)
                    }
                    line(row)
                }
                if entry.rows.count > Self.maxRows {
                    Text("+\(entry.rows.count - Self.maxRows) more")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 6)
                }
                Spacer(minLength: 10)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 5) {
            ProviderMark(size: 15, cornerRadius: 3.5)
            Text("All Accounts")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            // Claude's policy: badge only when a Claude account is shown.
            let hasClaude = entry.rows.contains { $0.account.providerID == ClaudeProvider.providerID }
            if ClaudePeakStatus.forProvider(hasClaude ? ClaudeProvider.providerID : nil, at: entry.date).isPeak {
                PeakBadge(size: 9)
            }
        }
    }

    private func line(_ row: AllAccountsEntry.Row) -> some View {
        let prefs = entry.prefs
        let layout = AccountCardLayout(snapshot: row.snapshot, modelSlotFallback: prefs.modelSlotFallback)
        let hero = layout.hero.window
        let figures = ([layout.hero] + layout.others)
            .map { "\($0.window?.shortTitle ?? $0.kind.shortName) \(Self.percent($0.window, prefs))" }
            .joined(separator: "  ·  ")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(row.account.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: Self.nameWidth, alignment: .leading)
                UsageBarView(
                    value: hero?.displayedPct(prefs.displayMode),
                    tint: hero?.tint(usageColors: prefs.usageColors) ?? Theme.accent,
                    height: 7,
                    lit: true
                )
                Text(verbatim: Self.percent(hero, prefs))
                    .font(Theme.figure(size: 15))
                    .foregroundStyle(hero == nil ? Theme.inkSecondary : Theme.ink)
                    .frame(width: Self.figureWidth, alignment: .trailing)
            }
            if row.snapshot != nil {
                Text(verbatim: figures)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.leading, Self.nameWidth + 10)
            }
        }
        // One VoiceOver element per account: its name and every window's
        // figure; the bar is decorative.
        .accessibilityElement(children: .combine)
    }

    private static func percent(_ window: UsageWindow?, _ prefs: Preferences) -> String {
        window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "--"
    }

    @ViewBuilder
    private var footer: some View {
        let soonest = entry.rows
            .compactMap { row in row.snapshot?.windows.first { $0.kind == .session }?.resetsAt }
            .filter { $0 > entry.date }
            .min()
        if let soonest {
            HStack(spacing: 3) {
                Image(systemName: "arrow.circlepath")
                Text("Next session reset:")
                ResetLineText(resetsAt: soonest, style: entry.prefs.resetStyle, now: entry.date, bare: true)
            }
            .font(.system(size: 9))
            .foregroundStyle(Theme.inkSecondary.opacity(0.9))
            .lineLimit(1)
        }
    }
}
