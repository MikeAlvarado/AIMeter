import SwiftUI
import WidgetKit
import UsageKit
#if os(iOS)
import AppIntents
#endif

/// One peak-hours badge for the whole widget, not repeated per account —
/// same rule the macOS menu bar popover already follows ("peak is
/// Claude-wide, not per account, so this isn't repeated per section").
struct AllAccountsWidgetView: View {
    let entry: AllAccountsEntry
    /// Each account renders its full window rows (reset lines included),
    /// same detail level as `AIMeterUsage` — not the density-optimized
    /// compact style, so it takes real vertical room. Two accounts is what
    /// comfortably fits a `.systemLarge` frame without scrolling; static,
    /// non-scrolling content is the safer choice for widgets, so this caps
    /// rather than fights WidgetKit's own gesture handling.
    private static let maxRows = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ClaudePeakStatus(at: entry.date).isPeak {
                peakBadge
                Divider().overlay(Theme.track)
            }
            if entry.rows.isEmpty {
                Text("Open AIMeter to load usage")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let visible = Array(entry.rows.prefix(Self.maxRows))
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider().overlay(Theme.track)
                    }
                    AccountRow(row: row, prefs: entry.prefs)
                }
                if entry.rows.count > Self.maxRows {
                    Text("+\(entry.rows.count - Self.maxRows) more")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Theme.card
        }
    }

    private var peakBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.danger)
            Text(ClaudePeakStatus(at: entry.date).title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
    }
}

/// One account's header (name + always-visible manual refresh, iOS only —
/// see `RefreshAccountIntent`) followed by its windows as full rows —
/// `WindowBarRow`, the same row `AIMeterUsage` renders, reset lines
/// included, with the grouped-reset-line rule (`WindowSlots.showsReset`)
/// every other surface already follows.
private struct AccountRow: View {
    let row: AllAccountsEntry.Row
    let prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ProviderIdentityView(
                    name: row.account.displayName,
                    iconSize: 15,
                    iconCornerRadius: 3.5,
                    font: .system(size: 12, weight: .semibold),
                    nameColor: Theme.ink,
                    planName: row.snapshot?.planName
                )
                Spacer(minLength: 0)
                #if os(iOS)
                Button(intent: RefreshAccountIntent(accountID: row.account.accountID)) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
                #endif
            }
            if let snapshot = row.snapshot {
                let slots = WindowSlots(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback).slots
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(slots.enumerated()), id: \.element.kind) { index, slot in
                        WindowBarRow(
                            kind: slot.kind,
                            window: slot.window,
                            prefs: prefs,
                            showsReset: WindowSlots.showsReset(at: index, in: slots),
                            moneySubtitle: prefs.creditsAmountSubtitle(for: slot.kind, snapshot: snapshot)
                        )
                    }
                }
            } else {
                Text("No usage data yet")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}
