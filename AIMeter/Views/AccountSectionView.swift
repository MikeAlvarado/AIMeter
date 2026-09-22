import SwiftUI
import UsageKit

/// One connected account's section: header (icon + nickname + plan pill,
/// tappable to push Provider Detail) + card with its rate-limit rows and
/// status footer. Shared by the Dashboard (one section per account) and,
/// where there's room, the macOS menu bar popover.
struct AccountSectionView: View {
    let usage: UsageModel.AccountUsage
    var iconSize: CGFloat = 22
    var iconCornerRadius: CGFloat = 6
    var font: Font = Theme.sectionHeader
    /// The Dashboard pushes Provider Detail from the header (needs an
    /// ancestor `NavigationStack`). The macOS menu bar popover has no
    /// navigation stack of its own, so it renders the same header as
    /// plain, non-interactive text instead — matching how the popover
    /// already behaved before there could be more than one account.
    var linksToDetail = true
    /// Off for the menu bar popover, which already brackets each section
    /// with its own dividers — same rule `UsageStatusFooter` documents for
    /// its other callers.
    var showsStatusDividers = true
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
    /// on 2+, since one account is enough to want a name), off for the
    /// menu bar popover and landscape, which follow the Dashboard's edits
    /// rather than making their own. The alert itself talks to
    /// `UsageModel` directly (see `renameAccountAlert`).
    var canRename = false

    /// The sheet is owned here rather than by each caller because all three
    /// surfaces that render an account (Dashboard, landscape, macOS menu
    /// bar popover) need the same recovery, and the failure they're
    /// recovering from belongs to this account, not to the screen.
    @State private var showingReconnect = false
    @State private var showingRename = false
    @State private var renameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Card {
                VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                    WindowRowsList(snapshot: usage.snapshot)
                    UsageStatusFooter(
                        snapshot: usage.snapshot,
                        error: usage.lastError,
                        showsDividers: showsStatusDividers,
                        reauthenticate: usage.needsReauthentication ? { showingReconnect = true } : nil,
                        offline: usage.isOffline
                    )
                }
            }
        }
        .sheet(isPresented: $showingReconnect) {
            ConnectClaudeSheet(reconnecting: usage.account)
        }
        .renameAccountAlert(for: usage.account.accountID, isPresented: $showingRename, name: $renameDraft)
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
        HStack(spacing: 8) {
            ProviderIdentityView(
                name: usage.account.displayName,
                iconSize: iconSize,
                iconCornerRadius: iconCornerRadius,
                font: font,
                nameColor: Theme.inkSecondary,
                planName: usage.snapshot?.planName
            )
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        // The Spacer between name and chevron is not hit-testable on its
        // own; without this, tapping the empty middle of the header did
        // nothing. Also what makes the header — not the card behind it —
        // own a long press anywhere along its width (context menu).
        .contentShape(Rectangle())
    }
}
