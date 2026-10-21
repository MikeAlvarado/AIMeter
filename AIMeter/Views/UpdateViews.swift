#if os(macOS)
import SwiftUI
import UsageKit

/// The update window (`AIMeterApp.updateWindowID`): the new version's notes
/// with "Restart to Update" and "Later" once an update is ready; this
/// version's notes with "Continue" after a version installed by hand; the
/// new features still off, with their buttons, after a version installed
/// from the notice; otherwise the check's progress ("Check for Updates…"
/// in the app menu opens it too).
struct UpdateWindow: View {
    @Environment(AppUpdater.self) private var updater
    @Environment(\.dismissWindow) private var dismissWindow
    /// The notes' height, measured: they scroll above the buttons once
    /// they are taller than most of the screen (a release's notes with
    /// their features' cards can be), and the buttons stay in sight.
    @State private var notesHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                notes
                    .padding([.horizontal, .top], 28)
                    .padding(.bottom, 22)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { notesHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(notesHeight > 0 ? notesHeight : Self.maxNotesHeight, Self.maxNotesHeight))
            actions
                .padding([.horizontal, .bottom], 28)
        }
        .frame(width: 440)
        .appBackground()
        .background(NonRestorableWindow())
        .onDisappear {
            if updater.notesToShow != nil { updater.dismissNotes() }
            if updater.offersToShow != nil { updater.dismissOffers() }
        }
    }

    /// Most of the screen, less the buttons and some air around the window.
    private static var maxNotesHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 200
    }

    @ViewBuilder
    private var notes: some View {
        if let ready = updater.readyUpdate {
            WhatsNewView(
                release: ready.notes ?? WhatsNew.Release(version: ready.version.description, items: []),
                title: String(localized: "AIMeter \(ready.version.description) is ready"),
                showsFeatures: false
            ) {
                if ready.notes == nil {
                    Link(String(localized: "Release notes on GitHub"), destination: ready.page)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                if !UpdateInstaller.canReplace(Bundle.main.bundleURL) {
                    Text("Move AIMeter to your Applications folder to update it in place. Until then, Restart to Update opens the download page.")
                        .font(.callout)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if let notes = updater.notesToShow {
            WhatsNewView(release: notes) { EmptyView() }
        } else if let offers = updater.offersToShow {
            WhatsNewView(release: offers, title: String(localized: "Turn on what's new")) { EmptyView() }
        } else {
            status
        }
    }

    @ViewBuilder
    private var actions: some View {
        if updater.readyUpdate != nil {
            HStack(spacing: 10) {
                CapsuleActionButton(title: String(localized: "Later"), prominent: false) {
                    updater.later()
                    close()
                }
                CapsuleActionButton(title: String(localized: "Restart to Update")) {
                    updater.install()
                }
                .keyboardShortcut(.defaultAction)
            }
        } else if updater.notesToShow != nil {
            CapsuleActionButton(title: String(localized: "Continue")) {
                updater.dismissNotes()
                close()
            }
            .keyboardShortcut(.defaultAction)
        } else if updater.offersToShow != nil {
            CapsuleActionButton(title: String(localized: "Continue")) {
                updater.dismissOffers()
                close()
            }
            .keyboardShortcut(.defaultAction)
        } else {
            CapsuleActionButton(title: String(localized: "OK")) { close() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var status: some View {
        HStack(spacing: 12) {
            if updater.phase == .checking || isDownloading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
            }
            Text(UpdateStatus.line(for: updater))
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var isDownloading: Bool {
        if case .downloading = updater.phase { true } else { false }
    }

    private func close() {
        dismissWindow(id: AIMeterApp.updateWindowID)
    }
}

/// One line for the updater's state, shared by the window and Settings.
enum UpdateStatus {
    @MainActor
    static func line(for updater: AppUpdater) -> String {
        switch updater.phase {
        case .idle:
            String(localized: "Version \(AppVersion.current?.description ?? "")")
        case .checking:
            String(localized: "Checking for updates…")
        case .upToDate:
            String(localized: "AIMeter is up to date.")
        case .downloading(let version):
            String(localized: "Downloading AIMeter \(version.description)…")
        case .ready(let prepared):
            String(localized: "AIMeter \(prepared.version.description) is ready")
        case .installing:
            String(localized: "Restarting…")
        case .failed(let message):
            String(localized: "Couldn't update: \(message)")
        }
    }
}

/// Settings → General → "Updates": the automatic check, the state, and
/// "Check Now" (or "Restart to Update" once one is ready).
struct UpdatesSettings: View {
    @Environment(AppUpdater.self) private var updater
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Updates"))
        Card {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                Toggle(isOn: $prefs.checksForUpdates) {
                    Text("Check for updates automatically")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)
                .disabled(!updater.isAvailable)
                Divider().overlay(Theme.track)
                HStack(spacing: 12) {
                    Text(UpdateStatus.line(for: updater))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if updater.readyUpdate != nil {
                        button(String(localized: "Restart to Update")) { AppChrome.openUpdateWindow() }
                    } else {
                        button(String(localized: "Check Now")) {
                            Task { await updater.check(userInitiated: true) }
                        }
                        .disabled(!updater.isAvailable || updater.phase == .checking)
                    }
                }
            }
        }
        .onChange(of: prefs.checksForUpdates) { _, on in
            updater.setAutomaticChecks(on)
        }
        SectionFootnote(text: updater.isAvailable
            ? String(localized: "AIMeter asks GitHub once a day for a newer version and downloads it in the background. It installs only when you restart from its notice.")
            : String(localized: "This copy isn't signed, so it can't update itself."))
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(Theme.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
    }
}

/// "AIMeter 2.1.0 is ready": the notice at the top of the menu bar popover
/// and the Dashboard while an update waits for a restart. Opens the
/// update window.
struct UpdateReadyNotice: View {
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        if let ready = updater.readyUpdate {
            Button {
                AppChrome.openUpdateWindow()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AIMeter \(ready.version.description) is ready")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text("See what's new and restart to update.")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
#endif
