#if os(macOS)
import SwiftUI
import UsageKit

/// The Mac's Settings window, at most six tabs (Mike's reorganization,
/// 2026-10-22, after a fresh review: seven didn't fit in French or
/// German, and "This Mac" next to "General" was a distinction nobody
/// makes): General (startup, updates, the Dock, how the numbers look,
/// refreshing, notifications, then AIMeter itself), Accounts (a list and
/// the selected account, `MacAccountsSettingsPage`), the two glance
/// surfaces, Claude Code (only where it has run on this Mac, and never in
/// the demo) and Privacy & data (iCloud and export over the explanation).
/// Built from the section views the iOS sheet uses
/// (`SettingsSections.swift`), at a fixed width so rows, pills and
/// switches never stretch across a wide window (the Accounts tab is wider:
/// a list beside a detail). Every toggle in it is a trailing switch
/// (`SettingsSwitchToggleStyle`).
struct MacSettingsView: View {
    @Environment(UsageModel.self) private var model
    @State private var tab: Tab = Self.launchTab ?? .general
    /// The account the Accounts tab shows (the first while none is).
    @State private var accountSelection: String?

    enum Tab: String, Hashable {
        case general, accounts, menuBar, notchIsland, claudeCode, privacy
    }

    /// `DEBUG` only: `-AIMeterSettingsTab <tab>` (a `Tab` raw value) opens
    /// Settings on that tab at launch (`AppDelegate`), so each tab can be
    /// checked and captured without a click.
    static var launchTab: Tab? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "AIMeterSettingsTab").flatMap(Tab.init(rawValue:))
        #else
        nil
        #endif
    }

    /// Wide enough for the menu bar previews and the island's wings, the
    /// same at every tab but Accounts, so the window keeps its width while
    /// switching between them.
    static let width: CGFloat = 540
    /// The long tabs scroll inside this; the short ones are their
    /// content's own height.
    static let scrollingHeight: CGFloat = 620

    /// Claude Code's tab: only where Claude Code has run (its logs folder
    /// exists), and never in the demo, which has nothing to configure.
    private var showsClaudeCode: Bool {
        !model.isDemoMode && Tour.claudeCodePresent
    }

    var body: some View {
        TabView(selection: $tab) {
            page(scrolls: true) { GeneralSettingsPage() }
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            MacAccountsSettingsPage(selection: $accountSelection)
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(Tab.accounts)
            page(scrolls: false) { MenuBarSettings() }
                .tabItem { Label("Menu bar", systemImage: "menubar.rectangle") }
                .tag(Tab.menuBar)
            page(scrolls: true) { NotchIslandSettings() }
                .tabItem { Label("Notch island", systemImage: "laptopcomputer") }
                .tag(Tab.notchIsland)
            if showsClaudeCode {
                page(scrolls: true) {
                    ClaudeSessionsSettings()
                    SettingsGap()
                    ClaudeCodeSettings()
                }
                .tabItem { Label("Claude Code", systemImage: "terminal") }
                .tag(Tab.claudeCode)
            }
            PrivacyView(showsDataControls: true)
                .frame(width: Self.width, height: Self.scrollingHeight)
                .tabItem { Label("Privacy & data", systemImage: "lock.shield") }
                .tag(Tab.privacy)
        }
        .toggleStyle(.settingsSwitch)
    }

    @ViewBuilder
    private func page<Content: View>(scrolls: Bool, @ViewBuilder content: () -> Content) -> some View {
        let stack = VStack(alignment: .leading, spacing: 10) { content() }
            .padding(20)
        if scrolls {
            ScrollView { stack }
                .frame(width: Self.width, height: Self.scrollingHeight)
                .appBackground()
        } else {
            stack
                .frame(width: Self.width, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .appBackground()
        }
    }
}

/// General: what AIMeter does on this Mac (starting at login, updating,
/// its Dock icon), how your numbers look, how often they refresh, which
/// notifications you get, and at the end AIMeter itself (the tour,
/// feedback, the source, the demo). The demo leads instead while nothing
/// is connected or while it is on.
private struct GeneralSettingsPage: View {
    @Environment(UsageModel.self) private var model

    var body: some View {
        if DemoModeSettings.leads(model) {
            DemoModeSettings()
            SettingsGap()
        }
        StartupSettings()
        SettingsGap()
        UpdatesSettings()
        SettingsGap()
        DockSettings()
        SettingsGap()
        AppearanceSettings()
        SettingsGap()
        AppIconSettings()
        if UsageRowsSettings.isOffered(model) {
            SettingsGap()
            UsageRowsSettings()
        }
        SettingsGap()
        BackgroundRefreshSettings()
        SettingsGap()
        ServiceStatusSettings()
        if PeakNotificationsSettings.isOffered {
            SettingsGap()
            PeakNotificationsSettings()
        }
        SettingsGap()
        TourSettings()
        SettingsGap()
        FeedbackSettings()
        SettingsGap()
        OpenSourceSettings()
        if !DemoModeSettings.leads(model) {
            SettingsGap()
            DemoModeSettings()
        }
    }
}

/// "Claude Code usage": reading the CLI's local logs for token counts,
/// and the popover's line. In the Claude Code tab, under its sessions.
struct ClaudeCodeSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Claude Code usage"))
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                Toggle(isOn: $prefs.claudeCodeUsageEnabled) {
                    Text("Read Claude Code's local usage logs")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)
                if prefs.claudeCodeUsageEnabled {
                    Divider().overlay(Theme.track)
                    Toggle(isOn: $prefs.menuBarShowsClaudeCodeLine) {
                        Text("Show today's total in the menu bar")
                            .font(Theme.rowTitle)
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.accent)
                }
            }
        }
        .onChange(of: prefs.claudeCodeUsageEnabled) { _, enabled in
            model.claudeCode?.setEnabled(enabled)
        }
        SectionFootnote(text: String(localized: "Adds up the tokens in ~/.claude/projects on this Mac, per model, and prices them at Anthropic's API list rates. Only the usage fields are decoded, never your prompts or Claude's replies, and nothing leaves this Mac. Off by default."))
    }
}

/// A Mac settings row: the title on the leading edge and a switch on the
/// trailing one, as in System Settings. SwiftUI's default on the Mac is a
/// checkbox *before* the title, which in these cards read as an iOS list
/// with a Mac control dropped into it. The visible title is hidden from
/// VoiceOver; the switch carries it, so the row is announced once.
struct SettingsSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

extension ToggleStyle where Self == SettingsSwitchToggleStyle {
    static var settingsSwitch: SettingsSwitchToggleStyle { SettingsSwitchToggleStyle() }
}
#endif
