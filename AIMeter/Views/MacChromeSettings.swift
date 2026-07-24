#if os(macOS)
import SwiftUI

/// How AIMeter presents itself on the Mac: the menu bar label's content,
/// whether the status item and Dock icon are shown at all, and whether the
/// app starts at login.
///
/// These are app-wide chrome, not provider data, so they live in Settings
/// rather than in Claude's Provider Detail next to `glanceMetric` — which
/// *is* account-dependent (its options come from the snapshot) and stays
/// where it is. The split is deliberate: "which window does the menu bar
/// read" is a Claude question, "does the menu bar show a number" is not.
struct MacChromeSettings: View {
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.openURL) private var openURL
    @State private var loginItem = LoginItemManager()

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Menu bar"))
        Card {
            Toggle(isOn: $prefs.menuBarShowsPercentage) {
                Text("Show percentage")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)
        }
        SectionFootnote(text: String(localized: "The menu bar always shows a gauge that fills with your usage. Turn this on to spell out the percentage beside it; with it off, the value is still in the tooltip. Which window it reads is set in Claude's settings."))

        sectionGap
        SectionHeader(title: String(localized: "Hiding AIMeter"))
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                Toggle(isOn: $prefs.hideDockIcon) {
                    Text("Hide Dock icon")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)

                Divider().overlay(Theme.track)

                Toggle(isOn: Binding(
                    get: { !prefs.statusItemVisible },
                    set: { prefs.statusItemVisible = !$0 }
                )) {
                    Text("Hide menu bar icon")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)

                if isFullyHidden {
                    Divider().overlay(Theme.track)
                    hiddenWarning
                }
            }
        }
        .onChange(of: prefs.hideDockIcon) { _, hidden in
            AppChrome.applyActivationPolicy(hidingDockIcon: hidden)
            // Switching policy drops the app out of the foreground; the user
            // is mid-settings, so put it back.
            NSApp.activate(ignoringOtherApps: true)
        }
        SectionFootnote(text: String(localized: "AIMeter keeps running and refreshing your usage either way — hiding only changes what you see. Quit still quits."))

        sectionGap
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
            String(localized: "With the Dock icon hidden, turn this on so AIMeter is back after a restart — otherwise you'll need to open it yourself."),
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

    /// With both icons off there is no visible UI at all, so the one way
    /// back in has to be spelled out *before* the user is looking at an
    /// empty screen wondering what happened.
    private var isFullyHidden: Bool {
        prefs.hideDockIcon && !prefs.statusItemVisible
    }

    private var hiddenWarning: some View {
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

    private var sectionGap: some View {
        Spacer().frame(height: Theme.sectionSpacing - 16)
    }
}
#endif
