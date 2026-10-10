#if os(macOS)
import SwiftUI
import UsageKit

private struct AccountListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The expanded layer: an incident notice while there is one, every
/// account as its own row (more than four scroll), and the footer's three
/// controls. Presents no sheets of its own — Connect, Sign in again and
/// Settings route through `AppChrome`, the same rule as the popover.
struct ExpandedContent: View {
    let island: NotchIslandModel
    let mode: NotchIslandGeometry.Mode
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
        .padding(.top, mode == .pill ? 4 : 12)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var accountList: some View {
        let rows = VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(island.accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 {
                    Rectangle().fill(NotchIslandStyle.hairline).frame(height: 1)
                }
                AccountRow(account: account)
            }
        }
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

/// One account: identity header, the full Vibe line with bars, and the
/// status line when there is something to say.
struct AccountRow: View {
    let account: NotchIslandModel.Account
    @Environment(UsageModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            SegmentLine(segments: account.segments, compact: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            statusLine
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(account.accessibilityLabel)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch account.status {
        case .fresh:
            EmptyView()
        case .stale(let caption):
            Text(caption)
                .font(Theme.caption)
                .foregroundStyle(NotchIslandStyle.reset)
        case .offline:
            Label(String(localized: "Offline — showing the last update."), systemImage: "wifi.slash")
                .font(Theme.caption)
                .foregroundStyle(NotchIslandStyle.reset)
        case .reauth:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(String(localized: "Sign-in expired — usage can't refresh."), systemImage: "exclamationmark.triangle")
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
