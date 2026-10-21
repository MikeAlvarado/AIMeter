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
        VStack(alignment: .leading, spacing: 10) {
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

            // "Open AIMeter" as the one labeled button, the icons beside it
            // carrying their names in the tooltip and for VoiceOver.
            HStack(spacing: 14) {
                // `revealMainWindow` reopens the Dashboard even if
                // `AppDelegate` closed it at launch (the common
                // hidden-Dock-icon case), since the scene registers its
                // reopen hook on first appearance, before any such close.
                // An account's own detail is a click on its block.
                openAIMeterButton

                Spacer()

                footerButton("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isRefreshing)

                // Discreet mode (see `DiscreetModeSettings`): the eye is
                // crossed and in the accent while it is on.
                if !model.accounts.isEmpty {
                    footerButton("Discreet mode", systemImage: prefs.discreetMode ? "eye.slash.fill" : "eye", isOn: prefs.discreetMode) {
                        prefs.discreetMode.toggle()
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                }

                // The popover is its own window with no main menu, so the
                // two shortcuts a Mac user reaches for blind are declared
                // here as well as in the app's menus.
                footerButton("Settings", systemImage: "gearshape") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)

                footerButton("Quit", systemImage: "power") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
        }
        .padding(10)
        .frame(width: 340)
        // No fill of its own: the popover sits on the system's own
        // material (Liquid Glass on macOS 26), like a menu.
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
            VStack(alignment: .leading, spacing: 4) {
                let shown = model.glanceAccounts(prefs)
                if shown.isEmpty {
                    // Every account marked for discreet mode: say so, so
                    // the empty list is not read as nothing connected.
                    Label("Hidden in discreet mode", systemImage: "eye.slash")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.vertical, 6)
                }
                ForEach(shown) { usage in
                    PopoverAccountBlock(usage: usage)
                }
                if !model.isDemoMode {
                    addAccountButton
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                if prefs.menuBarShowsClaudeCodeLine, !model.isDemoMode, !prefs.discreetMode, let line = model.claudeCode?.menuBarLine() {
                    Label(line, systemImage: "terminal")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
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

    @ViewBuilder
    private var openAIMeterButton: some View {
        let button = Button {
            AppChrome.revealMainWindow()
        } label: {
            Text("Open AIMeter")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 4)
        }
        if #available(macOS 26, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func footerButton(_ title: LocalizedStringKey, systemImage: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 22, height: 22)
                // The whole square, not just the glyph's strokes.
                .contentShape(Rectangle())
        }
        .buttonStyle(FooterIconButtonStyle(isOn: isOn))
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }

    /// Once at least one account is connected, this is the *only* way to add
    /// another from the menu bar — the Dashboard window (which has its own
    /// copy of this button) isn't reachable from here, and stays closed by
    /// default whenever the Dock icon is hidden (see `AppDelegate`), which
    /// is the common case for a menu-bar-first setup.
    private var addAccountButton: some View {
        Button {
            AppChrome.connect(.add)
        } label: {
            Label("Add account", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .contentShape(Rectangle())
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

/// The popover footer's icons: ink like the text around them (the accent
/// for a switch that is on), dimmed while pressed, and faint while
/// disabled (Refresh, mid-refresh) — a plain style with a fixed color
/// would hide both states.
private struct FooterIconButtonStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        Icon(configuration: configuration, isOn: isOn)
    }

    private struct Icon: View {
        let configuration: ButtonStyleConfiguration
        let isOn: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isOn ? Theme.accent : Theme.ink)
                .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.35)
        }
    }
}
#endif
