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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Card {
                VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                    WindowRowsList(snapshot: usage.snapshot)
                    UsageStatusFooter(snapshot: usage.snapshot, error: usage.lastError, showsDividers: showsStatusDividers)
                }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if linksToDetail {
            NavigationLink(value: usage.account.accountID) {
                headerContent(showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            headerContent(showsChevron: false)
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
    }
}
