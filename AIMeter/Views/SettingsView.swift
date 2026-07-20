import SwiftUI
import UsageKit

/// Public repo — shown in the "Open Source" settings row.
private let githubRepoURL = URL(string: "https://github.com/MikeAlvarado/AIMeter")!

struct SettingsView: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var prefs = prefs

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: String(localized: "Appearance"))
                Card {
                    SegmentedPill(
                        options: AppearanceMode.allCases.map { ($0, $0.label) },
                        selection: $prefs.appearance
                    )
                }

                sectionGap
                SectionHeader(title: String(localized: "Display"))
                Card {
                    SegmentedPill(
                        options: [DisplayMode.remaining, .used].map { ($0, $0.label) },
                        selection: $prefs.displayMode
                    )
                }
                SectionFootnote(text: String(localized: "Whether bars and percentages show how much you have left or how much you've used."))

                sectionGap
                SectionHeader(title: String(localized: "Reset timers"))
                Card {
                    SegmentedPill(
                        options: [ResetStyle.relative, .absolute].map { ($0, $0.label) },
                        selection: $prefs.resetStyle
                    )
                }
                SectionFootnote(text: String(localized: "Relative counts down to the reset. Absolute shows the local time. Tap any reset label on the dashboard to switch."))

                sectionGap
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
                SectionFootnote(text: refreshFootnote)

                sectionGap
                SectionHeader(title: String(localized: "Notifications"))
                NotificationTogglesCard()
                SectionFootnote(text: String(localized: "A local notification fires when the selected usage window resets."))

                sectionGap
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
                    }
                    .buttonStyle(.plain)
                }
                SectionFootnote(text: String(localized: "How connecting works, what the app can access, and where your data lives."))

                sectionGap
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
                    }
                    .buttonStyle(.plain)
                }
                SectionFootnote(text: String(localized: "AIMeter is free and open source. Visit the repository to read the code, file an issue, or contribute."))
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Settings")
        .onChange(of: prefs.refreshCadence) { _, newValue in
            #if os(iOS)
            BackgroundRefresh.scheduleNext()
            #else
            model.rebuildTimer(interval: newValue.interval)
            #endif
        }
    }

    private var sectionGap: some View {
        Spacer().frame(height: Theme.sectionSpacing - 16)
    }

    private var refreshFootnote: String {
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

#if os(iOS)
/// Sheet wrapper with a Done button, matching the reference presentation.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .tint(Theme.accent)
                    }
                }
        }
    }
}
#endif
