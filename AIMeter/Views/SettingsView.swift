import SwiftUI
import UsageKit

struct SettingsView: View {
    @Environment(UsageModel.self) private var model
    @Environment(PreferencesModel.self) private var prefs

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
