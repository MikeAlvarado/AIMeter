#if os(macOS)
import SwiftUI
import UsageKit

private struct PopoverListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct MenuBarView: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.openSettings) private var openSettings
    @State private var showingConnect = false
    /// The account list's natural height, measured — see `accountList`.
    @State private var listHeight: CGFloat = 0
    /// Past this the list scrolls instead of growing the popover.
    private static let maxListHeight: CGFloat = 360

    /// Peak is Claude's policy: shown when any connected account is a
    /// Claude account, off-peak otherwise.
    private var peak: ClaudePeakStatus {
        let hasClaude = model.accounts.contains { $0.account.providerID == ClaudeProvider.providerID }
        return ClaudePeakStatus.forProvider(hasClaude ? ClaudeProvider.providerID : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            if peak.isPeak {
                peakBadgeRow
                Divider().overlay(Theme.track)
            }
            if let incident = model.activeIncident {
                ServiceStatusBanner(
                    providerName: ProviderCatalog.displayName(for: incident.providerID),
                    status: incident.status,
                    fallbackURL: ProviderCatalog.statusPageURL(for: incident.providerID),
                    compact: true
                )
            }

            if model.needsConnection {
                DisconnectedPrompt(buttonLabel: "Connect Claude account", verticalPadding: 10) {
                    showingConnect = true
                }
            } else {
                accountList
            }

            Divider().overlay(Theme.track)

            HStack {
                // The popover has no navigation stack, so it can't reach
                // Provider Detail (Peak hours, Forecast, per-account
                // notifications, disconnect) — this is the only way back to
                // the Dashboard window that can. `revealMainWindow` reopens
                // it even if `AppDelegate` closed it at launch (the common
                // hidden-Dock-icon case), since the scene registers its
                // reopen hook on first appearance, before any such close.
                Button {
                    AppChrome.revealMainWindow()
                } label: {
                    Image(systemName: "macwindow")
                }
                .help(String(localized: "Open AIMeter"))
                .accessibilityLabel(Text("Open AIMeter"))

                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isRefreshing)

                Spacer()

                // The popover is its own window with no main menu, so the
                // two shortcuts a Mac user reaches for blind are declared
                // here as well as in the app's Usage menu.
                Button("Settings…") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
        .background(Theme.background)
        .sheet(isPresented: $showingConnect) {
            ConnectClaudeSheet()
        }
    }

    /// The accounts, in a `ScrollView` whose height is the content's own
    /// measured height up to `maxListHeight` — a handful of accounts fit
    /// the popover, more scroll. Measured explicitly rather than
    /// `.frame(maxHeight:)` on the scroll view: a `MenuBarExtra` window
    /// sizes itself to its content's *ideal* size, and a `ScrollView`
    /// reports an ideal height of zero for this content, which collapsed
    /// the whole list to a two-pixel strip under the divider (seen on
    /// macOS 26 with the 1.5 popover; the dashboard, in a regular window,
    /// was unaffected).
    private var accountList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                ForEach(model.accounts) { usage in
                    AccountSectionView(
                        usage: usage,
                        iconSize: 20,
                        iconCornerRadius: 5,
                        font: Theme.sectionHeader,
                        linksToDetail: false,
                        showsStatusDividers: false
                    )
                }
                if !model.isDemoMode {
                    addAccountButton
                }
                if prefs.menuBarShowsClaudeCodeLine, !model.isDemoMode, let line = model.claudeCode?.menuBarLine() {
                    Divider().overlay(Theme.track)
                    Label(line, systemImage: "terminal")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: PopoverListHeightKey.self, value: proxy.size.height)
                }
            }
        }
        .onPreferenceChange(PopoverListHeightKey.self) { listHeight = $0 }
        .frame(height: min(listHeight, Self.maxListHeight))
    }

    /// Once at least one account is connected, this is the *only* way to add
    /// another from the menu bar — the Dashboard window (which has its own
    /// copy of this button) isn't reachable from here, and stays closed by
    /// default whenever the Dock icon is hidden (see `AppDelegate`), which
    /// is the common case for a menu-bar-first setup.
    private var addAccountButton: some View {
        Button {
            showingConnect = true
        } label: {
            Label("Add account", systemImage: "plus.circle")
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }

    private var peakBadgeRow: some View {
        HStack {
            PeakBadge(size: 13, title: peak.title, titleFont: Theme.sectionHeader)
            Spacer()
        }
        .help(peak.subtitle)
        .accessibilityElement(children: .combine)
    }
}
#endif
