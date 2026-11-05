#if os(macOS)
import SwiftUI
import UsageKit

/// The expanded layer: an incident notice while there is one, every
/// account in one grid (`AccountGrid`; more than four scroll), Claude
/// Code's sessions while there are any (`SessionsSection`), and the
/// footer's three controls. Presents no sheets of its own — Connect, Sign in again and
/// Settings route through `AppChrome`, the same rule as the popover.
struct ExpandedContent: View {
    let island: NotchIslandModel
    /// The body's inset from the slab, which every section and the
    /// header's wings (`CollapsedRow.fill`) share, so all of them start and
    /// end at the same two edges.
    static let horizontalPadding: CGFloat = 18
    @State private var listHeight: CGFloat = 0
    private static let maxListHeight: CGFloat = 360
    private static let scrollsPast = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let incident = island.incident {
                Label(incident, systemImage: "exclamationmark.icloud")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchIslandStyle.label)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            accountList
            if !island.sessions.isEmpty {
                Rectangle().fill(NotchIslandStyle.hairline).frame(height: 1)
                SessionsSection(sessions: island.sessions)
            }
            Rectangle().fill(NotchIslandStyle.hairline).frame(height: 1)
            IslandFooter()
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var accountList: some View {
        // Edge to edge: the separators spread the columns over the width.
        let rows = AccountGrid(accounts: island.accounts, primaryID: island.primaryID).frame(maxWidth: .infinity)
        if island.accounts.count > Self.scrollsPast {
            // Measured, not `.frame(maxHeight:)`: a `ScrollView` reports an
            // ideal height of zero for this content (see `MenuBarView`).
            // With `onGeometryChange`, not a preference: in this panel on
            // macOS 27 `onPreferenceChange` delivered only its default (the
            // slab hit it first), which would leave the list 0 pt tall.
            ScrollView {
                rows.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(listHeight, Self.maxListHeight))
        } else {
            rows
        }
    }
}

/// Every account's windows in cells of one width that share its line
/// edge to edge, one gap and a separator between them, so its bars are
/// equally wide and equally spaced whether it reports two windows or three
/// (Mike, 2026-11-05: an earlier grid put every account in shared columns,
/// and an account with no session, Ultra, then began a column late). The
/// rows span the island edge to edge, where the sessions, the dividers and
/// the footer start and end. A window's figures and its reset are always
/// one line at 12 pt, the name in full (Mike, 2026-11-05: no reset under
/// the bar, no smaller size, no shortened name): in the absolute style the
/// clock time when every line holds it, else the island shows the
/// countdown ("↻2d 16h"), which fits in every language
/// (`NotchIslandGeometry.expandedWidth`); credits' amount, shown in full
/// when it fits, falls back to the amount spent alone. Headers, dividers and status lines
/// span the width. With two or more accounts, a click anywhere on one
/// puts its figures in the sneak (and the menu bar's), and the one there
/// now has its header marked. Laid out by `IslandColumns`, not a SwiftUI
/// `Grid`: a `Grid` whose separator columns were the flexible ones laid
/// out wider than the island it was offered (measured: 451 pt for 366
/// offered), and the island clipped both ends of every line (3.2.0).
struct AccountGrid: View {
    let accounts: [NotchIslandModel.Account]
    /// The account the sneak shows.
    var primaryID: String?

    var body: some View {
        // One line per account at one size, the reset beside its figure:
        // the clock time when every line holds it, else the short form
        // (the countdown, or credits' amount spent), for the whole island
        // at once.
        ViewThatFits(in: .horizontal) {
            columns(shortReset: false)
            columns(shortReset: true)
        }
    }

    private func columns(shortReset: Bool) -> some View {
        let picks = accounts.count > 1
        return IslandColumns(gap: 8) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                let line = index * IslandColumns.linesPerAccount
                let count = account.segments.count
                if index > 0 {
                    Rectangle().fill(NotchIslandStyle.hairline).frame(height: 1)
                        .padding(.vertical, 12)
                        .islandCell(.span, line: line)
                }
                AccountHeader(account: account, isSelected: picks && account.id == primaryID, isPickable: picks)
                    .padding(.bottom, 10)
                    .islandCell(.span, line: line + 1)
                ForEach(Array(account.segments.enumerated()), id: \.offset) { cell, segment in
                    if cell > 0 {
                        Text(verbatim: "|")
                            .font(NotchIslandStyle.font(12))
                            .foregroundStyle(NotchIslandStyle.separator)
                            .picksAccount(account.id, if: picks)
                            .islandCell(.separator(cell, of: count), line: line + 2)
                    }
                    SegmentText(segment: segment, compact: false, shortReset: shortReset)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(segment.accessibilityLabel)
                        .picksAccount(account.id, if: picks)
                        .islandCell(.segment(cell, of: count), line: line + 2)
                    SegmentBar(segment: segment)
                        .padding(.top, 4)
                        .picksAccount(account.id, if: picks)
                        .islandCell(.bar(cell, of: count), line: line + 3)
                }
                if account.status != .fresh {
                    AccountStatusLine(account: account)
                        .padding(.top, 10)
                        .islandCell(.span, line: line + 4)
                }
            }
        }
    }
}

/// The account's identity, and a spinner while it refreshes; marked
/// while its figures are the sneak's.
struct AccountHeader: View {
    let account: NotchIslandModel.Account
    var isSelected = false
    var isPickable = false
    @State private var isHovering = false

    var body: some View {
        identity
            .background { IslandRowHighlight(isSelected: isSelected, isHovering: isPickable && isHovering) }
            .onHover { isHovering = $0 }
            .picksAccount(account.id, if: isPickable)
    }

    private var identity: some View {
        HStack(spacing: 8) {
            ProviderIdentityView(
                name: account.name,
                iconSize: 16,
                iconCornerRadius: 4,
                font: .system(size: 12, weight: .semibold),
                nameColor: .white,
                planName: account.planName,
                icon: account.icon
            )
            Spacer(minLength: 0)
            if account.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(NotchIslandStyle.control)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(account.accessibilityLabel)
    }
}

/// The line under an account's windows, only when there is something to
/// say: stale, offline, a dead login or the raw error.
struct AccountStatusLine: View {
    let account: NotchIslandModel.Account
    @Environment(UsageModel.self) private var model
    @Environment(\.notchIslandActions) private var actions

    var body: some View {
        switch account.status {
        case .fresh:
            EmptyView()
        case .stale(let caption):
            Text(caption)
                .font(Theme.caption)
                .foregroundStyle(NotchIslandStyle.reset)
        case .offline:
            Label(String(localized: "Offline. Showing the last update."), systemImage: "wifi.slash")
                .font(Theme.caption)
                .foregroundStyle(NotchIslandStyle.reset)
        case .reauth:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(String(localized: "Sign-in expired. Usage can't refresh."), systemImage: "exclamationmark.triangle")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
                Spacer(minLength: 0)
                Button(String(localized: "Sign in again")) {
                    if let connected = model.usage(for: account.id)?.account {
                        AppChrome.connect(.reconnect(connected))
                        actions?.close()
                    }
                }
                .buttonStyle(.plain)
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(Theme.caption)
                .foregroundStyle(Theme.danger)
                .lineLimit(3)
        }
    }
}

/// Refresh and Open AIMeter together on the left, Settings alone on the
/// right — icon-only, labelled for VoiceOver and the tooltip. Refresh is
/// disabled while a refresh runs and in demo mode (nothing real to
/// fetch). The controls that open a window close the island on the way;
/// Refresh leaves it open. No keyboard shortcut: the panel is never key.
struct IslandFooter: View {
    @Environment(UsageModel.self) private var model
    @Environment(\.notchIslandActions) private var actions

    var body: some View {
        HStack(spacing: 10) {
            // The outer glyphs sit on the body's edges, like everything above.
            control("arrow.clockwise", String(localized: "Refresh"), alignment: .leading) {
                Task { await model.refreshAll() }
            }
            .disabled(model.isRefreshing || model.isDemoMode)
            Rectangle().fill(NotchIslandStyle.separator).frame(width: 1, height: 14)
            control("macwindow", String(localized: "Open AIMeter")) {
                AppChrome.revealMainWindow()
                actions?.close()
            }
            Spacer()
            if let ready = AppUpdater.shared.readyUpdate {
                // An update waits for a restart: its notice, beside Settings.
                control("arrow.down.circle.fill", String(localized: "AIMeter \(ready.version.description) is ready"), tint: Theme.accent) {
                    AppChrome.openUpdateWindow()
                    actions?.close()
                }
            }
            control("gearshape", String(localized: "Settings…"), alignment: .trailing) {
                AppChrome.openSettings()
                actions?.close()
            }
        }
    }

    private func control(_ symbol: String, _ title: String, tint: Color = NotchIslandStyle.control, alignment: Alignment = .center, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 20, alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
#endif
