#if os(macOS)
import SwiftUI
import UsageKit

private struct AccountListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The expanded layer: an incident notice while there is one, every
/// account in one grid (`AccountGrid`; more than four scroll), and the
/// footer's three controls. Presents no sheets of its own — Connect, Sign in again and
/// Settings route through `AppChrome`, the same rule as the popover.
struct ExpandedContent: View {
    let island: NotchIslandModel
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
            Rectangle().fill(NotchIslandStyle.hairline).frame(height: 1)
            IslandFooter()
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var accountList: some View {
        // Centered: the grid is as wide as its columns, never wider.
        let rows = AccountGrid(accounts: island.accounts).frame(maxWidth: .infinity)
        if island.accounts.count > Self.scrollsPast {
            // Measured, not `.frame(maxHeight:)`: a `ScrollView` reports an
            // ideal height of zero for this content (see `MenuBarView`).
            ScrollView {
                rows.background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: AccountListHeightKey.self, value: proxy.size.height)
                    }
                }
            }
            .onPreferenceChange(AccountListHeightKey.self) { listHeight = $0 }
            .frame(height: min(listHeight, Self.maxListHeight))
        } else {
            rows
        }
    }
}

/// Every account in one grid, so their windows sit in the same columns
/// with the same gap between them, whatever each one reports, and the
/// grid centered in the island. Each column is as wide as its widest
/// figures; the bars sit in a row of their own and take the column's
/// width without widening it (`gridCellUnsizedAxes`), so every bar in a
/// column has the same track. Headers, dividers and status lines span
/// the grid the same way. The figures are 12 pt; when the grid would not
/// fit the island's width, 11, then 10.
struct AccountGrid: View {
    let accounts: [NotchIslandModel.Account]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            grid(scale: 1)
            grid(scale: 11 / 12)
            grid(scale: 10 / 12)
        }
    }

    private func grid(scale: CGFloat) -> some View {
        let columns = accounts.map(\.segments.count).max() ?? 0
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 {
                    Rectangle().fill(NotchIslandStyle.hairline).frame(height: 1)
                        .gridCellUnsizedAxes(.horizontal)
                        .padding(.vertical, 12)
                }
                AccountHeader(account: account)
                    .gridCellUnsizedAxes(.horizontal)
                    .padding(.bottom, 10)
                GridRow(alignment: .firstTextBaseline) {
                    ForEach(0..<columns, id: \.self) { column in
                        let segment = account.segments.indices.contains(column) ? account.segments[column] : nil
                        if column > 0 {
                            if segment != nil {
                                Text(verbatim: "|")
                                    .font(NotchIslandStyle.font(12 * scale))
                                    .foregroundStyle(NotchIslandStyle.separator)
                            } else {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            }
                        }
                        if let segment {
                            SegmentText(segment: segment, compact: false, scale: scale)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(segment.accessibilityLabel)
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        if column > 0 {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                        if account.segments.indices.contains(column) {
                            SegmentBar(segment: account.segments[column])
                                .gridCellUnsizedAxes(.horizontal)
                                .padding(.top, 4)
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
                if account.status != .fresh {
                    AccountStatusLine(account: account)
                        .gridCellUnsizedAxes(.horizontal)
                        .padding(.top, 10)
                }
            }
        }
    }
}

/// The account's identity, and a spinner while it refreshes.
struct AccountHeader: View {
    let account: NotchIslandModel.Account

    var body: some View {
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
/// fetch). No keyboard shortcut: the panel is never key.
struct IslandFooter: View {
    @Environment(UsageModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            control("arrow.clockwise", String(localized: "Refresh")) {
                Task { await model.refreshAll() }
            }
            .disabled(model.isRefreshing || model.isDemoMode)
            Rectangle().fill(NotchIslandStyle.separator).frame(width: 1, height: 14)
            control("macwindow", String(localized: "Open AIMeter")) {
                AppChrome.revealMainWindow()
            }
            Spacer()
            control("gearshape", String(localized: "Settings…")) {
                AppChrome.openSettings()
            }
        }
    }

    private func control(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchIslandStyle.control)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
#endif
