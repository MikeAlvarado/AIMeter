import SwiftUI
import WidgetKit
import UsageKit
#if os(iOS)
import AppIntents
#endif

/// One peak-hours badge for the whole widget, not repeated per account —
/// same rule the macOS menu bar popover already follows ("peak is
/// Claude-wide, not per account, so this isn't repeated per section").
/// The standard layout; `CondensedAccountsView` is the other.
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
        Group {
            if entry.layout == .condensed {
                CondensedAccountsView(entry: entry)
            } else {
                standard
            }
        }
        .containerBackground(for: .widget) {
            Theme.card
        }
    }

    private var standard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Claude's policy: badge only when a Claude account is shown.
            let hasClaude = entry.rows.contains { $0.account.providerID == ClaudeProvider.providerID }
            let peak = ClaudePeakStatus.forProvider(hasClaude ? ClaudeProvider.providerID : nil, at: entry.date)
            if peak.isPeak {
                HStack {
                    PeakBadge(size: 10, title: peak.title)
                    Spacer(minLength: 0)
                }
            }
            if entry.rows.isEmpty {
                Text("Open AIMeter to load usage")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let visible = Array(entry.rows.prefix(Self.maxRows))
                // The accounts share the height: the first at the top, the
                // last at the bottom, the room left over between them.
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Spacer(minLength: 14)
                    }
                    AccountRow(row: row, prefs: entry.prefs, now: entry.date)
                }
                if entry.rows.count > Self.maxRows {
                    Text("+\(entry.rows.count - Self.maxRows) more")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkSecondary)
                }
                if visible.count < 2 {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One account's header (name + always-visible manual refresh, iOS only —
/// see `RefreshAccountIntent`) followed by the app's card composition
/// (4.0): its most urgent window as the protagonist and the others as
/// compact lines, `WidgetHero` and `WidgetCompactRows`, the small
/// widget's own pieces, decided by the same `AccountCardLayout`.
private struct AccountRow: View {
    let row: AllAccountsEntry.Row
    let prefs: Preferences
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                ProviderIdentityView(
                    name: row.account.displayName,
                    iconSize: 15,
                    iconCornerRadius: 3.5,
                    font: .system(size: 12, weight: .semibold),
                    nameColor: Theme.ink,
                    planName: row.snapshot?.planName,
                    icon: row.account.icon
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
                let layout = AccountCardLayout(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback)
                WidgetHero(
                    kind: layout.hero.kind,
                    window: layout.hero.window,
                    prefs: prefs,
                    now: now,
                    moneySubtitle: prefs.creditsAmountSubtitle(for: layout.hero.kind, snapshot: snapshot),
                    figureSize: 34
                )
                .padding(.bottom, 4)
                WidgetCompactRows(slots: layout.others, prefs: prefs)
            } else {
                Text("No usage data yet")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}
