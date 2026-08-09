#if os(macOS)
import SwiftUI
import UsageKit

/// How AIMeter presents itself on the Mac: the menu bar label's content,
/// whether the status item and Dock icon are shown at all, and whether the
/// app starts at login.
///
/// Most of this is app-wide chrome, not provider data, so it lives in
/// Settings rather than in Claude's Provider Detail. `glanceMetric` (which
/// window the gauge reads) and the new `primaryAccountID` (which account)
/// are the one exception living here too: with several connected accounts,
/// there's no longer a single unambiguous "the" account whose Provider
/// Detail could own that control the way it used to when only one existed.
struct MacChromeSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.openURL) private var openURL
    @State private var loginItem = LoginItemManager()

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Menu bar"))
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                if model.accounts.count > 1 {
                    SegmentedPill(
                        options: model.accounts.map { ($0.account.accountID, $0.account.displayName) },
                        selection: primaryAccountBinding
                    )
                    Divider().overlay(Theme.track)
                }
                SegmentedPill(
                    options: UsageSnapshot.glanceOptions(
                        for: model.primaryAccountUsage(preferredID: prefs.primaryAccountID)?.snapshot,
                        modelSlotFallback: prefs.modelSlotFallback
                    ).map { ($0, $0.shortName) },
                    selection: $prefs.glanceMetric
                )
                Divider().overlay(Theme.track)
                Toggle(isOn: $prefs.menuBarShowsPercentage) {
                    Text("Show percentage")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)
            }
        }
        SectionFootnote(text: menuBarFootnote)

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

    /// Writes through to `prefs.primaryAccountID`; reads through
    /// `UsageModel.primaryAccountUsage` so the picker always shows a
    /// connected account even if the stored id is stale (e.g. that account
    /// was disconnected elsewhere).
    private var primaryAccountBinding: Binding<String> {
        Binding(
            get: { model.primaryAccountUsage(preferredID: prefs.primaryAccountID)?.account.accountID ?? ClaudeKeychainCredentialSource.legacyAccountID },
            set: { prefs.primaryAccountID = $0 }
        )
    }

    private var menuBarFootnote: String {
        model.accounts.count > 1
            ? String(localized: "The menu bar shows one account and one window at a time — pick which above. Turn on the percentage to spell it out beside the gauge; with it off, the value is still in the tooltip.")
            : String(localized: "The menu bar always shows a gauge that fills with your usage. Pick which window it reads above. Turn this on to spell out the percentage beside it; with it off, the value is still in the tooltip.")
    }
}
#endif
