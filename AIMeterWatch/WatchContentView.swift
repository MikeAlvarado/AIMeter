import SwiftUI
import UsageKit

/// Every account with its windows, as the phone's Dashboard rows, and a
/// Refresh that asks the iPhone; with nothing sent yet, where to connect.
struct WatchContentView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.accounts.isEmpty {
                    ContentUnavailableView {
                        Label("Open AIMeter on iPhone", systemImage: "iphone")
                    } description: {
                        Text("Connect an account there. The Watch shows what your iPhone last fetched.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("AIMeter")
            // Opening the app is the moment to ask, when what it holds
            // is older than the phone's own staleness mark.
            .onAppear { store.requestRefreshIfStale() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.requestRefresh()
                    } label: {
                        // watchOS fills a top-bar button with the tint; the
                        // glyph has to be told it is on it, or it vanishes.
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.white)
                    }
                    .disabled(store.isRequesting)
                    .accessibilityLabel("Refresh")
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(store.accounts) { account in
                Section {
                    if let snapshot = store.snapshots[account.accountID] {
                        WatchAccountRows(snapshot: snapshot, prefs: store.prefs)
                    } else {
                        Text("No usage data yet")
                            .font(.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                } header: {
                    // The trio in a row, as every caller lays it out.
                    HStack(spacing: 6) {
                        ProviderIdentityView(
                            name: account.displayName,
                            iconSize: 14,
                            iconCornerRadius: 3.5,
                            font: .caption.weight(.semibold),
                            nameColor: Theme.ink,
                            planName: store.snapshots[account.accountID]?.planName,
                            icon: account.icon,
                            compactPill: true
                        )
                    }
                    // The system's header sits on the first card; a little
                    // air under it keeps the name off the bars.
                    .padding(.bottom, 5)
                }
            }
            Section {
                footer
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if store.requestFailed {
            Text("iPhone not reachable. Showing the last update.")
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)
        } else if let receivedAt = store.receivedAt {
            Text(UsageFormatting.updatedLabel(receivedAt))
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

/// One account's windows: name and figure, the bar, the reset line (live
/// under a day, like the widgets'), with the grouped-reset rule every
/// other surface follows.
private struct WatchAccountRows: View {
    let snapshot: UsageSnapshot
    let prefs: Preferences

    var body: some View {
        let slots = WindowSlots(snapshot: snapshot, modelSlotFallback: prefs.modelSlotFallback).slots
        ForEach(Array(slots.enumerated()), id: \.element.kind) { index, slot in
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(slot.kind.shortName)
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer(minLength: 4)
                    Text(slot.window.map { "\(Int($0.displayedPct(prefs.displayMode)))%" } ?? "--")
                        .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                }
                UsageBarView(
                    value: slot.window?.displayedPct(prefs.displayMode),
                    tint: slot.window?.tint(usageColors: prefs.usageColors) ?? Theme.accent
                )
                if WindowSlots.showsReset(at: index, in: slots), let resetsAt = slot.window?.resetsAt {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.circlepath")
                        ResetLineText(resetsAt: resetsAt, style: prefs.resetStyle, now: Date())
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkSecondary)
                } else if let amount = prefs.creditsAmountSubtitle(for: slot.kind, snapshot: snapshot) {
                    Text(amount)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
