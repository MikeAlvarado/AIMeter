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
    @Environment(\.dismiss) private var dismiss
    /// The account list's natural height, measured — see `accountList`.
    @State private var listHeight: CGFloat = 0
    /// The list's bottom edge in the scroll view's space: past the
    /// visible height while there is more to scroll to.
    @State private var listBottom: CGFloat = 0
    @State private var loginItem = LoginItemManager()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Past this the list scrolls instead of growing the popover.
    private static let maxListHeight: CGFloat = 480

    /// Peak is Claude's policy: shown when any connected account is a
    /// Claude account, off-peak otherwise.
    private var peak: ClaudePeakStatus {
        let hasClaude = model.accounts.contains { $0.account.providerID == ClaudeProvider.providerID }
        return ClaudePeakStatus.forProvider(hasClaude ? ClaudeProvider.providerID : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if peak.isPeak {
                peakBadgeRow
                    .padding(.horizontal, 6)
            }
            if let incident = model.activeIncident {
                ServiceStatusBanner(
                    providerName: ProviderCatalog.displayName(for: incident.providerID),
                    status: incident.status,
                    fallbackURL: ProviderCatalog.statusPageURL(for: incident.providerID),
                    compact: true
                )
            }
            // Only while an update waits for a restart.
            UpdateReadyNotice()

            if model.needsConnection {
                VStack(spacing: 12) {
                    DisconnectedPrompt(buttonLabel: "Connect an account", verticalPadding: 10) {
                        AppChrome.connect(.add)
                    }
                }
                .padding(6)
            } else {
                accountList
            }

            // The footer reads like a menu (4.0.1, Mike's reference): one
            // item a line, its shortcut at the trailing edge, the switches
            // as switches. The popover is its own window with no main menu,
            // so the shortcuts a Mac user reaches for blind are declared
            // here as well as in the app's menus.
            VStack(spacing: 0) {
                PopoverMenuSeparator()
                // `revealMainWindow` reopens the Dashboard even if
                // `AppDelegate` closed it at launch (the common
                // hidden-Dock-icon case), since the scene registers its
                // reopen hook on first appearance, before any such close.
                PopoverMenuItem("Open AIMeter") {
                    AppChrome.revealMainWindow()
                }
                PopoverMenuItem("Refresh All", shortcut: "⌘R") {
                    Task { await model.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isRefreshing)
                // Once an account is connected this is the only way to add
                // another from the menu bar: the Dashboard window stays
                // closed by default while the Dock icon is hidden.
                if !model.isDemoMode {
                    PopoverMenuItem("Add Account…", shortcut: "⌘N") {
                        AppChrome.connect(.add)
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
                PopoverMenuSeparator()
                // Discreet mode (see `DiscreetModeSettings`).
                if !model.accounts.isEmpty {
                    PopoverMenuToggle("Discreet Mode", shortcut: "⇧⌘D", isOn: Binding(
                        get: { prefs.discreetMode },
                        set: { prefs.discreetMode = $0 }
                    ))
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                }
                PopoverMenuToggle("Open at Login", isOn: Binding(
                    get: { loginItem.isEnabled || loginItem.needsApproval },
                    set: { loginItem.setEnabled($0) }
                ))
                PopoverMenuSeparator()
                PopoverMenuItem("Settings…", shortcut: "⌘,") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                    AppChrome.closeMenuBarPopover()
                }
                .keyboardShortcut(",", modifiers: .command)
                PopoverMenuItem("Quit AIMeter", shortcut: "⌘Q") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(8)
        .frame(width: PopoverTableMetrics.popoverWidth)
        // The system draws this window as clear glass on macOS 26 and
        // later, and 4.0.0 put nothing over it: whatever window sat under
        // the popover showed through and the secondary text could not be
        // read (Mike, 2026-10-21). Apple's answer for clear glass is a
        // dimming layer, so the app's background lies over it, mostly
        // opaque: the glass still shows at the edges and under the footer,
        // and the accounts sit on cards of their own. Solid under Reduce
        // Transparency.
        .background(Theme.background.opacity(reduceTransparency ? 1 : 0.78))
        // The login item can change in System Settings while AIMeter runs.
        .onAppear {
            loginItem.refreshStatus()
            AppChrome.dismissMenuBarPopover = { dismiss() }
        }
        // Its window, so a route that opens another can close it
        // (`AppChrome.closeMenuBarPopover`).
        .background(WindowReader { AppChrome.menuBarPopoverWindow = $0 })
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
        ScrollViewReader { scroller in
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                let shown = model.glanceAccounts(prefs)
                if shown.isEmpty {
                    // Every account marked for discreet mode: say so, so
                    // the empty list is not read as nothing connected.
                    Label("Hidden in discreet mode", systemImage: "eye.slash")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                } else if let lastUpdatedLabel {
                    Text(verbatim: lastUpdatedLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                }
                ForEach(shown) { usage in
                    PopoverAccountRow(usage: usage)
                }
                if prefs.menuBarShowsClaudeCodeLine, !model.isDemoMode, !prefs.discreetMode, let line = model.claudeCode?.menuBarLine() {
                    // The glyph's own edge on the cards' content edge, which
                    // a `Label` set a few points to the left.
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                        Text(verbatim: line)
                    }
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: PopoverListHeightKey.self, value: proxy.size.height)
                }
            }
            // Where the list ends below the visible part, for the hint.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(Self.listSpace)).maxY
            } action: { listBottom = $0 }
            Color.clear.frame(height: 0).id(Self.listEnd)
        }
        .coordinateSpace(name: Self.listSpace)
        .onPreferenceChange(PopoverListHeightKey.self) { listHeight = $0 }
        .frame(height: min(listHeight, Self.maxListHeight))
        // More below the fold (Mike, 2026-10-21: a card cut at the bottom
        // edge didn't say there was more): the list fades out at its
        // bottom edge, and a chevron there scrolls to the end. Both go once
        // the end is in sight.
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .black.opacity(moreBelow ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 44)
            }
        }
        .overlay(alignment: .bottom) {
            if moreBelow {
                Button {
                    withAnimation(.easeOut(duration: 0.3)) { scroller.scrollTo(Self.listEnd, anchor: .bottom) }
                } label: {
                    Image(systemName: "chevron.compact.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 44, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("More accounts"))
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: moreBelow)
        }
    }

    /// Whether the list goes on below what the popover shows.
    private var moreBelow: Bool {
        listHeight > Self.maxListHeight && listBottom > Self.maxListHeight + 8
    }
    private static let listSpace = "popoverList"
    private static let listEnd = "popoverListEnd"

    /// When the accounts last refreshed, the newest of them (the
    /// Dashboard's subtitle): each row only speaks up once it is stale.
    private var lastUpdatedLabel: String? {
        model.glanceAccounts(prefs).compactMap(\.snapshot?.fetchedAt).max().map { UsageFormatting.updatedLabel($0) }
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

/// Hands its view's window to `onWindow` once it is in one.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { onWindow(window) }
        }
    }
}
#endif
