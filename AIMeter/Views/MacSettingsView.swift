#if os(macOS)
import SwiftUI
import UsageKit

/// The Mac's Settings window: the sections the iOS sheet stacks in one
/// list (`SettingsSections.swift`), spread over toolbar tabs the way a
/// Mac app's settings are — General, the two glance surfaces, Claude Code
/// and Privacy & data — at a fixed width, so rows, pills and switches
/// never stretch across a wide window. Every toggle in it is a trailing
/// switch (`SettingsSwitchToggleStyle`).
struct MacSettingsView: View {
    @Environment(UsageModel.self) private var model
    @State private var tab: Tab = Self.launchTab ?? .general

    enum Tab: String, Hashable {
        case general, notchIsland, menuBar, claudeCode, privacy
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
    /// same at every tab so the window keeps its width while switching.
    static let width: CGFloat = 540
    /// The long tabs scroll inside this; the short ones are their
    /// content's own height.
    static let scrollingHeight: CGFloat = 620

    var body: some View {
        TabView(selection: $tab) {
            page(scrolls: true) { GeneralSettingsPage() }
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            page(scrolls: true) { NotchIslandSettings() }
                .tabItem { Label("Notch island", systemImage: "laptopcomputer") }
                .tag(Tab.notchIsland)
            page(scrolls: false) { MenuBarSettings() }
                .tabItem { Label("Menu bar", systemImage: "menubar.rectangle") }
                .tag(Tab.menuBar)
            // The demo has no Claude Code section to configure (it shows
            // fabricated sessions), same as the single list hid the card.
            if !model.isDemoMode {
                page(scrolls: false) {
                    ClaudeSessionsSettings()
                    SettingsGap()
                    ClaudeCodeSettings()
                }
                .tabItem { Label("Claude Code", systemImage: "terminal") }
                .tag(Tab.claudeCode)
            }
            PrivacyView()
                .frame(width: Self.width, height: Self.scrollingHeight)
                .tabItem { Label("Privacy & data", systemImage: "lock.shield") }
                .tag(Tab.privacy)
        }
        .toggleStyle(.settingsSwitch)
        .onChange(of: model.isDemoMode) { _, demo in
            if demo, tab == .claudeCode { tab = .general }
        }
    }

    @ViewBuilder
    private func page<Content: View>(scrolls: Bool, @ViewBuilder content: () -> Content) -> some View {
        let stack = VStack(alignment: .leading, spacing: 10) { content() }
            .padding(20)
        if scrolls {
            ScrollView { stack }
                .frame(width: Self.width, height: Self.scrollingHeight)
                .background(Theme.background)
        } else {
            stack
                .frame(width: Self.width, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .background(Theme.background)
        }
    }
}

/// General: the iOS list's sections, plus the Mac's own chrome — hiding
/// the icons and opening at login.
private struct GeneralSettingsPage: View {
    @Environment(UsageModel.self) private var model

    var body: some View {
        if DemoModeSettings.leads(model) {
            DemoModeSettings()
            SettingsGap()
        }
        AppearanceSettings()
        SettingsGap()
        AppIconSettings()
        if PeakNotificationsSettings.isOffered {
            SettingsGap()
            PeakNotificationsSettings()
        }
        SettingsGap()
        BackgroundRefreshSettings()
        SettingsGap()
        ServiceStatusSettings()
        if ExportSettings.isOffered(model) {
            SettingsGap()
            ExportSettings()
        }
        SettingsGap()
        HidingSettings()
        SettingsGap()
        StartupSettings()
        SettingsGap()
        UpdatesSettings()
        SettingsGap()
        TourSettings()
        SettingsGap()
        OpenSourceSettings()
        if !DemoModeSettings.leads(model) {
            SettingsGap()
            DemoModeSettings()
        }
    }
}

/// "Usage": reading the CLI's local logs for token counts, and the
/// popover's line. Under "Sessions" (`ClaudeSessionsSettings`) in the
/// Claude Code tab.
struct ClaudeCodeSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Usage"))
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
