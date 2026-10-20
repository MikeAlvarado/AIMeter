import SwiftUI
import WidgetKit
import UsageKit

/// The all-accounts widget's condensed layout (Edit Widget → Layout):
/// one line per account, its name, a bar per window slot in the columns
/// the slots make, and its first window's figure, under the slots'
/// names; then the soonest session reset of them all as a live
/// countdown. Six accounts fit where the standard layout's full rows
/// hold two; what a line gives up is the reset under each bar and the
/// iOS refresh button. The columns are kinds: an account's bar sits in
/// the column of its kind, so two providers' accounts never share a
/// column by position alone, and a column an account lacks is faded.
struct CondensedAccountsView: View {
    let entry: AllAccountsEntry
    static let maxRows = 6
    private static let nameWidth: CGFloat = 64
    private static let figureWidth: CGFloat = 34

    var body: some View {
        let rows = Array(entry.rows.prefix(Self.maxRows))
        let columns = Self.columns(of: entry)
        VStack(alignment: .leading, spacing: 9) {
            header
            if entry.rows.isEmpty {
                Text("Open AIMeter to load usage")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                captions(columns)
                ForEach(rows) { row in
                    line(row, columns: columns)
                }
                if entry.rows.count > Self.maxRows {
                    Text("+\(entry.rows.count - Self.maxRows) more")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The columns are the slots of the first account that has three,
    /// else two; an account with fewer keeps its missing column faded.
    static func columns(of entry: AllAccountsEntry) -> [UsageWindow.Kind] {
        let slotKinds = entry.rows.compactMap { row in
            row.snapshot.map { WindowSlots(snapshot: $0, modelSlotFallback: entry.prefs.modelSlotFallback).slots.map(\.kind) }
        }
        return slotKinds.first { $0.count > 2 } ?? slotKinds.first ?? [.session, .weekly]
    }

    /// The caption over a column: the first shown window of that kind
    /// names it with its real length ("Month" for a 30-day week).
    static func caption(for kind: UsageWindow.Kind, in entry: AllAccountsEntry) -> String {
        entry.rows.lazy.compactMap { $0.snapshot?.window(for: kind) }.first?.shortTitle ?? kind.shortName
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

    private func captions(_ columns: [UsageWindow.Kind]) -> some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: Self.nameWidth, height: 1)
            ForEach(Array(columns.enumerated()), id: \.offset) { _, kind in
                Text(Self.caption(for: kind, in: entry))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Color.clear.frame(width: Self.figureWidth, height: 1)
        }
        .accessibilityHidden(true)
    }

    private func line(_ row: AllAccountsEntry.Row, columns: [UsageWindow.Kind]) -> some View {
        let slots = row.snapshot.map { WindowSlots(snapshot: $0, modelSlotFallback: entry.prefs.modelSlotFallback).slots } ?? []
        let mode = entry.prefs.displayMode
        return HStack(spacing: 6) {
            Text(row.account.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .frame(width: Self.nameWidth, alignment: .leading)
            ForEach(columns.indices, id: \.self) { index in
                let slot = slots.first { $0.kind == columns[index] }
                let window = slot?.window
                UsageBarView(
                    value: window?.displayedPct(mode),
                    tint: window?.tint(usageColors: entry.prefs.usageColors) ?? Theme.accent
                )
                .opacity(slot == nil ? 0.35 : 1)
            }
            Text(slots.first?.window.map { "\(Int($0.displayedPct(mode)))%" } ?? "--")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(width: Self.figureWidth, alignment: .trailing)
        }
        // One VoiceOver element per account: its name and its session's
        // figure; the bars are decorative.
        .accessibilityElement(children: .combine)
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
