#if os(macOS)
import SwiftUI
import UsageKit

/// "Sessions" (Settings, Claude Code tab): Claude Code's sessions in the
/// notch island, the "needs you" notification, and the optional hooks,
/// installed or removed with one click (see "Claude Code sessions" in the
/// repo-root CLAUDE.md). Each switch restarts or stops the monitor
/// through `AppChrome.updateClaudeSessions`.
struct ClaudeSessionsSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.openURL) private var openURL
    /// Whether macOS lets AIMeter read where the menu bar's items are, checked again
    /// whenever the app comes forward (after a trip to System Settings).
    @State private var accessibilityTrusted = AccessibilityAccess.isTrusted
    private var accessibility: AccessibilityState {
        AccessibilityState(trusted: accessibilityTrusted, confirmedBefore: prefs.claudeSessionsAccessibilityConfirmed)
    }
    private var monitor: ClaudeSessionMonitor { .shared }

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Sessions"))
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                Toggle(isOn: $prefs.claudeSessionsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show sessions in the notch")
                            .font(Theme.rowTitle)
                            .foregroundStyle(Theme.ink)
                        if prefs.claudeSessionsEnabled, !prefs.notchIslandEnabled {
                            Text("The notch island is off.")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
                .tint(Theme.accent)
                if prefs.claudeSessionsEnabled {
                    Divider().overlay(Theme.track)
                    Toggle(isOn: $prefs.claudeSessionsPets) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("A pet for each session")
                                .font(Theme.rowTitle)
                                .foregroundStyle(Theme.ink)
                            Text("Off, a spinner and a count instead.")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .tint(Theme.accent)
                    Divider().overlay(Theme.track)
                    Toggle(isOn: $prefs.claudeSessionsShowsName) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show the session's name")
                                .font(Theme.rowTitle)
                                .foregroundStyle(Theme.ink)
                            Text("Beside the notch while the island is closed. Hovering shows it either way.")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .tint(Theme.accent)
                    if prefs.claudeSessionsShowsName {
                        Divider().overlay(Theme.track)
                        Toggle(isOn: avoidsMenusBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Avoid covering the menu bar")
                                    .font(Theme.rowTitle)
                                    .foregroundStyle(Theme.ink)
                                Text("The island shrinks before it covers the open app's menus or the icons on the right. This needs Accessibility, used only to read where they are.")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                        .tint(Theme.accent)
                        if prefs.claudeSessionsAvoidsMenus, let remedy = accessibility.remedy {
                            accessibilityRow(remedy)
                        }
                    }
                }
                Divider().overlay(Theme.track)
                Toggle(isOn: notifyBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notify when a session needs you")
                            .font(Theme.rowTitle)
                            .foregroundStyle(Theme.ink)
                        // Only the hooks can tell that a session asks.
                        Text(monitor.hooksInstalled
                            ? String(localized: "When a session asks for your permission.")
                            : String(localized: "When a session asks for your permission, once the hooks below are in."))
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .tint(Theme.accent)
                if model.notificationsBlocked {
                    blockedRow
                }
                Divider().overlay(Theme.track)
                hooksRow
                if prefs.claudeSessionsEnabled {
                    Divider().overlay(Theme.track)
                    answersRow
                }
            }
        }
        .onChange(of: prefs.claudeSessionsEnabled) { _, _ in AppChrome.updateClaudeSessions() }
        .onChange(of: prefs.claudeSessionsNotify) { _, _ in AppChrome.updateClaudeSessions() }
        .onChange(of: prefs.claudeSessionsAnswers) { _, _ in AppChrome.updateClaudeSessions() }
        .task {
            monitor.refreshHooksState()
            accessibilityTrusted = AccessibilityAccess.check(prefs: prefs) == .granted
            await model.refreshNotificationAuthorization()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                accessibilityTrusted = AccessibilityAccess.check(prefs: prefs) == .granted
            }
        }
        SectionFootnote(text: String(localized: "AIMeter reads only whether each session is working, waiting or done, and its title and folder, from the logs in ~/.claude/projects. It never reads your prompts or Claude's replies, and nothing leaves this Mac. Installing the hooks adds AIMeter to ~/.claude/settings.json and backs the file up first; everything else in it stays as it is."))
    }

    /// Turning it on asks macOS for the Accessibility permission with the
    /// system's own prompt, which leads to System Settings, but only while
    /// the permission never worked (`AccessibilityState.mayPrompt`): one a
    /// differently signed copy holds is mended in System Settings, as the
    /// row under the switch says.
    private var avoidsMenusBinding: Binding<Bool> {
        Binding(
            get: { prefs.claudeSessionsAvoidsMenus },
            set: { enabled in
                prefs.claudeSessionsAvoidsMenus = enabled
                guard enabled else { return }
                accessibilityTrusted = AccessibilityAccess.request(prefs: prefs) == .granted
            }
        )
    }

    /// What to do, while the switch is on and the permission isn't.
    private func accessibilityRow(_ remedy: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            Text(remedy)
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(String(localized: "Open Settings")) {
                if let url = AccessibilityAccess.settingsURL {
                    openURL(url)
                }
            }
            .buttonStyle(.plain)
            .font(Theme.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
    }

    /// Turning the notification on asks for the system permission first;
    /// a denial leaves the switch off and says where to change it.
    private var notifyBinding: Binding<Bool> {
        Binding(
            get: { prefs.claudeSessionsNotify },
            set: { enabled in
                guard enabled else {
                    prefs.claudeSessionsNotify = false
                    return
                }
                Task { @MainActor in
                    let allowed = await NotificationScheduler.ensureAuthorization()
                    model.notificationsBlocked = !allowed
                    if allowed { prefs.claudeSessionsNotify = true }
                }
            }
        )
    }

    /// What the hooks add, whether they are in, and the one button.
    private var hooksRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permission prompts")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                    Text(monitor.hooksInstalled
                        ? String(localized: "Claude Code's hooks tell AIMeter when a session asks.")
                        : String(localized: "Needs Claude Code's hooks, added in one click."))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
                if monitor.hooksInstalled {
                    Button(String(localized: "Remove")) {
                        // Answering needs the hooks: without them it is off.
                        prefs.claudeSessionsAnswers = false
                        AppChrome.updateClaudeSessions()
                        monitor.removeHooks()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(String(localized: "Install")) {
                        monitor.installHooks()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                }
            }
            if let error = monitor.hooksError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
            }
        }
    }

    /// "Answer from the island", off by default: the hooks' answering
    /// mode, installed when it is switched on (`ClaudeSessionMonitor`), and
    /// under it, while on, what it means for the user's data.
    private var answersRow: some View {
        @Bindable var prefs = prefs
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $prefs.claudeSessionsAnswers) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Answer from the island")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                    Text("Approve or deny a session's permission prompts and stop a session from the island. Claude Code still asks in its own window too, and the first answer counts.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .tint(Theme.accent)
            if prefs.claudeSessionsAnswers {
                Label(String(localized: "AIMeter receives nothing. All of this stays on your Mac."), systemImage: "lock.fill")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var blockedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(String(localized: "Notifications are off in system Settings."), systemImage: "bell.slash")
                .font(Theme.caption)
                .foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 0)
            Button(String(localized: "Open Settings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
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
