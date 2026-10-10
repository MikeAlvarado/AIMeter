import SwiftUI
import UsageKit

/// Public repo — shown in the "Open Source" settings row.
private let githubRepoURL = URL(string: "https://github.com/MikeAlvarado/AIMeter")!

// The sections of Settings both platforms show, one view each (header,
// card, footnote), so the iOS sheet stacks them in one list
// (`SettingsView`) and the Mac spreads them over its Settings window's
// tabs (`MacSettingsView`) without either copying the other. A section
// never adds the gap around itself; the list that places it does.

/// The space between two sections of a Settings list.
struct SettingsGap: View {
    var body: some View {
        Spacer().frame(height: Theme.sectionSpacing - 16)
    }
}

/// "Demo mode": Exit Demo while the demo runs, View Demo otherwise. The
/// lists put it first while the demo runs or nothing is connected (it is
/// then the one thing to do) and last once a real account is.
struct DemoModeSettings: View {
    @Environment(UsageModel.self) private var model

    var body: some View {
        SectionHeader(title: String(localized: "Demo mode"))
        if model.isDemoMode {
            Card {
                Button(role: .destructive) {
                    model.exitDemoMode()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "eye.slash")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.danger)
                            .frame(width: 28, height: 28)
                            .background(Theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("Exit Demo")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            SectionFootnote(text: String(localized: "You're viewing sample data. Exit to connect your real Claude account."))
        } else {
            // "View Demo" swaps in fabricated accounts in memory only
            // (`UsageModel.enterDemoMode`), so it is safe to offer even
            // with real accounts connected — Exit Demo reloads them
            // untouched.
            Card {
                Button {
                    model.enterDemoMode()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "eye")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28, height: 28)
                            .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("View Demo")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            SectionFootnote(text: model.needsConnection
                ? String(localized: "Explore every screen with sample data before connecting your real Claude account.")
                : String(localized: "Explore every screen with sample data. Your real accounts come back untouched when you exit."))
        }
    }

    /// Whether the list leads with this section rather than ending on it.
    static func leads(_ model: UsageModel) -> Bool {
        model.isDemoMode || model.needsConnection
    }
}

/// "Appearance", "Display" and "Reset timers": how every surface draws
/// the figures.
struct AppearanceSettings: View {
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Appearance"))
        Card {
            SegmentedPill(
                options: AppearanceMode.allCases.map { ($0, $0.label) },
                selection: $prefs.appearance
            )
        }

        SettingsGap()
        SectionHeader(title: String(localized: "Display"))
        Card {
            SegmentedPill(
                options: [DisplayMode.remaining, .used].map { ($0, $0.label) },
                selection: $prefs.displayMode
            )
        }
        SectionFootnote(text: String(localized: "Whether bars and percentages show how much you have left or how much you've used."))

        SettingsGap()
        SectionHeader(title: String(localized: "Reset timers"))
        Card {
            SegmentedPill(
                options: [ResetStyle.relative, .absolute].map { ($0, $0.label) },
                selection: $prefs.resetStyle
            )
        }
        SectionFootnote(text: String(localized: "Relative counts down to the reset. Absolute shows the local time. Tap any reset label on the dashboard to switch."))
    }
}

/// The one Peak-hours alerts toggle. Lists show it only while a peak
/// schedule is in force — none is today (the policy is retired, see
/// `ClaudePeakSchedule`), so the toggle would arm alerts for a window
/// that never comes.
struct PeakNotificationsSettings: View {
    @Environment(UsageModel.self) private var model

    static var isOffered: Bool { ClaudePeakSchedule.current != nil }

    var body: some View {
        SectionHeader(title: String(localized: "Notifications"))
        Card {
            Toggle(isOn: Binding(
                get: { model.peakNotificationsEnabled },
                set: model.setPeakNotificationsEnabled
            )) {
                Text("Peak-hours alerts")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)
        }
        .task {
            await model.refreshNotificationAuthorization()
        }
        SectionFootnote(text: String(localized: "Notify when Claude's documented weekday peak window starts or ends. This is one Claude-wide policy, not a per-account setting — every connected account's rate-limit alerts still have their own toggles on that account's own screen."))
    }
}

/// "Check service status", mirrored into the model as it changes.
struct ServiceStatusSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Service status"))
        Card {
            Toggle(isOn: $prefs.checksServiceStatus) {
                Text("Check service status")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)
        }
        .onChange(of: prefs.checksServiceStatus) { _, newValue in
            model.setChecksServiceStatus(newValue)
        }
        SectionFootnote(text: String(localized: "Reads the provider's public status page whenever AIMeter refreshes, so an outage shows as an incident instead of an account error. Nothing about you is sent."))
    }
}

/// The refresh cadence, rescheduling the platform's background work as it
/// changes.
struct BackgroundRefreshSettings: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        SectionHeader(title: String(localized: "Background refresh"))
        Card {
            HStack {
                Text("Refresh usage")
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Picker("", selection: $prefs.refreshCadence) {
                    ForEach(RefreshCadence.allCases, id: \.self) { cadence in
                        Text(cadence.label).tag(cadence)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .tint(Theme.accent)
            }
        }
        .onChange(of: prefs.refreshCadence) { _, newValue in
            #if os(iOS)
            BackgroundRefresh.scheduleNext()
            #else
            model.rebuildRefreshSchedule(interval: newValue.interval)
            #endif
        }
        SectionFootnote(text: footnote)
    }

    private var footnote: String {
        var text: String
        #if os(iOS)
        text = String(localized: "AIMeter refreshes usage in the background when iOS permits it, then updates your widgets. Timing depends on battery, connectivity, and how often you use the app.")
        #else
        text = String(localized: "AIMeter refreshes usage on this schedule while the menu bar app is running, then updates your widgets.")
        #endif
        if let scheduled = prefs.lastScheduledAt {
            let minutes = max(0, Int(Date().timeIntervalSince(scheduled) / 60))
            text += "\n" + String(localized: "Scheduled \(minutes) minutes ago.")
        }
        return text
    }
}

/// The row that pushes Privacy & data (iOS — the Mac gives it a tab).
struct PrivacyLinkSettings: View {
    var body: some View {
        Card {
            NavigationLink {
                PrivacyView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("Privacy & data")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        SectionFootnote(text: String(localized: "How connecting works, what the app can access, and where your data lives."))
    }
}

/// "Open Source": the repository, in the browser.
struct OpenSourceSettings: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Card {
            Button {
                openURL(githubRepoURL)
            } label: {
                HStack(spacing: 12) {
                    Image("GitHubIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .frame(width: 28, height: 28)
                        .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("Open Source")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        SectionFootnote(text: String(localized: "AIMeter is free and open source. Visit the repository to read the code, file an issue, or contribute."))
    }
}
