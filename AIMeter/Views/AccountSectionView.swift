import SwiftUI
import UsageKit

/// One connected account's card (4.0): its identity inside the card at the
/// top (icon + nickname + plan pill, tappable to push Provider Detail),
/// then its most urgent window as the protagonist and the rest as compact
/// rows (`AccountCardLayout`), and the status tail only when there is
/// something to say. Shared by the Dashboard (one card per account) and
/// iPhone landscape; the macOS menu bar popover has its own denser block
/// (`PopoverAccountBlock`).
struct AccountSectionView: View {
    let usage: UsageModel.AccountUsage
    /// The Dashboard pushes Provider Detail from the header (needs an
    /// ancestor `NavigationStack`). Landscape has no navigation stack, so
    /// it renders the same header as plain, non-interactive content.
    var linksToDetail = true
    /// Reorder actions for the header's context menu, supplied by the
    /// Dashboard (the one surface that reorders) and nil at either end of
    /// the list. They exist alongside drag-and-drop rather than instead of
    /// it: a drag is unreachable with VoiceOver or Switch Control, and a
    /// menu is also the only part of this that announces itself — nothing
    /// about a card suggests it can be dragged.
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?
    /// Whether the header's context menu offers "Rename…" — on for the
    /// Dashboard (every account: unlike the reorder actions it isn't gated
    /// on 2+, since one account is enough to want a name), off for
    /// landscape, which follows the Dashboard's edits rather than making
    /// its own. The alert itself talks to `UsageModel` directly (see
    /// `renameAccountAlert`).
    var canRename = false
    /// Whether the protagonist carries its 24-hour sparkline — on for the
    /// Dashboard, off for landscape, which stays a glance.
    var showsSparkline = false

    /// The sheet is owned here rather than by each caller because both
    /// surfaces that render this card need the same recovery, and the
    /// failure they're recovering from belongs to this account, not to the
    /// screen.
    @State private var showingReconnect = false
    @State private var showingRename = false
    @State private var renameDraft = ""
    @State private var showingIconPicker = false
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        let layout = AccountCardLayout(snapshot: usage.snapshot, modelSlotFallback: prefs.modelSlotFallback)
        VStack(alignment: .leading, spacing: 20) {
            header
            HeroWindowView(
                kind: layout.hero.kind,
                window: layout.hero.window,
                moneySubtitle: prefs.creditsAmountSubtitle(for: layout.hero.kind, snapshot: usage.snapshot),
                sparkline: showsSparkline
                    ? HistoryChartData(samples: model.timeline(for: usage.account.accountID, kind: layout.hero.kind), range: .day, now: Date())
                    : nil
            )
            if !layout.others.isEmpty {
                CompactWindowRows(slots: layout.others, snapshot: usage.snapshot)
            }
            statusTail
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .sheet(isPresented: $showingReconnect) {
            ConnectAccountSheet(reconnecting: usage.account)
        }
        .renameAccountAlert(for: usage.account.accountID, isPresented: $showingRename, name: $renameDraft)
        .sheet(isPresented: $showingIconPicker) {
            AccountIconPicker(accountID: usage.account.accountID)
        }
    }

    /// The error, the reconnect prompt, the incident line, and "Updated X
    /// ago" once the card's figures are stale; nothing at all on a normal
    /// day, since the Dashboard's header says when it last refreshed.
    @ViewBuilder
    private var statusTail: some View {
        let hasError = usage.lastError != nil || usage.needsReauthentication
        if hasError || usage.snapshot?.isStale == true {
            VStack(alignment: .leading, spacing: 8) {
                UsageStatusFooter(
                    snapshot: usage.snapshot,
                    error: usage.lastError,
                    reauthenticate: usage.needsReauthentication ? { showingReconnect = true } : nil,
                    offline: usage.isOffline,
                    serviceIncident: model.incidentNote(for: usage),
                    updated: .whenStale
                )
            }
        }
    }

    /// The context menu goes on the header alone, not the whole section:
    /// the Dashboard puts a drag on the section, and both gestures start
    /// from the same long press, so overlapping them makes which one wins
    /// a coin toss. Split by area they stay predictable — hold the card to
    /// drag it, hold the header for the menu.
    @ViewBuilder
    private var header: some View {
        if !canRename && moveUp == nil && moveDown == nil {
            headerLink
        } else {
            headerLink.contextMenu { accountMenu }
        }
    }

    @ViewBuilder
    private var headerLink: some View {
        if linksToDetail {
            NavigationLink(value: usage.account.accountID) {
                headerContent(showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            headerContent(showsChevron: false)
        }
    }

    @ViewBuilder
    private var accountMenu: some View {
        if canRename {
            Button {
                renameDraft = usage.account.displayName
                showingRename = true
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button {
                showingIconPicker = true
            } label: {
                Label("Change icon…", systemImage: "sparkle")
            }
        }
        if let moveUp {
            Button(action: moveUp) {
                Label("Move up", systemImage: "arrow.up")
            }
        }
        if let moveDown {
            Button(action: moveDown) {
                Label("Move down", systemImage: "arrow.down")
            }
        }
    }

    private func headerContent(showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            ProviderIdentityView(
                name: usage.account.displayName,
                iconSize: 26,
                iconCornerRadius: 8,
                font: .headline,
                nameColor: Theme.ink,
                planName: usage.snapshot?.planName,
                icon: usage.account.icon
            )
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        // The Spacer between name and chevron is not hit-testable on its
        // own; without this, tapping the empty middle of the header did
        // nothing. Also what makes the header — not the card around it —
        // own a long press anywhere along its width (context menu).
        .contentShape(Rectangle())
    }
}
