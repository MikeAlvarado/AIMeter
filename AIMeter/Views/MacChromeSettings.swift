#if os(macOS)
import SwiftUI
import UsageKit

/// The Dock icon (General): whether AIMeter shows one at all. Hiding the
/// menu bar icon is the first row of the Menu bar tab
/// (`MenuBarVisibilityToggle`), where someone who wants it gone looks for
/// it; until 4.1 both sat in a "Hiding AIMeter" card of the This Mac tab.
struct DockSettings: View {
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Dock"))
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                Toggle(isOn: $prefs.hideDockIcon) {
                    Text("Hide Dock icon")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)
                if HiddenEverywhereWarning.applies(prefs) {
                    Divider().overlay(Theme.track)
                    HiddenEverywhereWarning()
                }
            }
        }
        .onChange(of: prefs.hideDockIcon) { _, hidden in
            AppChrome.applyActivationPolicy(hidingDockIcon: hidden)
            // Switching policy drops the app out of the foreground; the user
            // is mid-settings, so put it back.
            NSApp.activate(ignoringOtherApps: true)
            // The Dock tile that comes back draws the bundle's icon: the
            // look picked in Settings goes on it again, next turn, once the
            // tile exists.
            if !hidden {
                let icon = prefs.appIcon
                DispatchQueue.main.async { AppChrome.applyAppIcon(icon) }
            }
        }
        SectionFootnote(text: String(localized: "AIMeter keeps running and refreshing your usage either way. Hiding only changes what you see. Quit still quits."))
    }
}

/// The Menu bar tab's first row: whether the status item is there at all
/// (`statusItemVisible`), with why it is off while the notch island has
/// taken its place, and the warning once nothing at all is visible.
struct MenuBarVisibilityToggle: View {
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        Toggle(isOn: $prefs.statusItemVisible) {
            Text("Show in menu bar")
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.ink)
        }
        .tint(Theme.accent)
        if prefs.notchIslandEnabled, !prefs.statusItemVisible {
            Label(String(localized: "Hidden while the notch island is on."), systemImage: "eye.slash")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        if HiddenEverywhereWarning.applies(prefs) {
            HiddenEverywhereWarning()
        }
    }
}

/// With both icons off and no island there is no visible UI at all, so
/// the one way back in has to be spelled out *before* the user is looking
/// at an empty screen wondering what happened. The island counts as
/// visible UI: its footer opens the Dashboard.
struct HiddenEverywhereWarning: View {
    static func applies(_ prefs: PreferencesModel) -> Bool {
        prefs.hideDockIcon && !prefs.statusItemVisible && !prefs.notchIslandEnabled
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text("With both hidden, AIMeter has no visible controls. Open it again from Finder or Spotlight to bring this window back.")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// "Open at Login", read live from `SMAppService` (`LoginItemManager`),
/// with the approval and the hidden-Dock nudge rows.
struct StartupSettings: View {
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.openURL) private var openURL
    @State private var loginItem = LoginItemManager()

    var body: some View {
        SectionHeader(title: String(localized: "Startup"))
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                Toggle(isOn: Binding(
                    get: { loginItem.isEnabled || loginItem.needsApproval },
                    set: { loginItem.setEnabled($0) }
                )) {
                    Text("Open at Login")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)

                if loginItem.needsApproval {
                    Divider().overlay(Theme.track)
                    approvalRow
                }
                if let error = loginItem.lastError {
                    Divider().overlay(Theme.track)
                    Text(error)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if needsLoginItemNudge {
                    Divider().overlay(Theme.track)
                    nudgeRow
                }
            }
        }
        // The user may have revoked the login item in System Settings while
        // the app kept running, so re-read rather than trust a stale value.
        .onAppear { loginItem.refreshStatus() }
        SectionFootnote(text: String(localized: "Starts AIMeter automatically after you log in, so your usage keeps updating without opening it yourself."))
    }

    /// Hiding the icons without a login item means a restart leaves AIMeter
    /// not running, with no icon to notice its absence by — worth saying
    /// while the user is right here deciding.
    private var needsLoginItemNudge: Bool {
        prefs.hideDockIcon && !loginItem.isEnabled && !loginItem.needsApproval
    }

    private var nudgeRow: some View {
        Label(
            String(localized: "With the Dock icon hidden, turn this on so AIMeter is back after a restart. Otherwise you'll need to open it yourself."),
            systemImage: "info.circle"
        )
        .font(Theme.caption)
        .foregroundStyle(Theme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// macOS adds the login item without a modal prompt, then waits for the
    /// user to allow it. Saying nothing here would leave a toggle that looks
    /// on but does nothing at the next restart.
    private var approvalRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(
                String(localized: "Waiting for approval in System Settings."),
                systemImage: "exclamationmark.triangle"
            )
            .font(Theme.caption)
            .foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 0)
            Button(String(localized: "Open Settings")) {
                if let url = LoginItemManager.settingsURL {
                    openURL(url)
                }
            }
            .buttonStyle(.plain)
            .font(Theme.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
    }
}
#endif
