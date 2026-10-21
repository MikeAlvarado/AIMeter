import SwiftUI
import UsageKit

/// Settings as one list — the iOS sheet. The Mac's Settings window shows
/// the same sections over tabs instead (`MacSettingsView`); both are
/// built from the section views in `SettingsSections.swift`. The list is
/// the general settings; each account's own are on its page, reached
/// from the account list (`AccountListSettings`).
struct SettingsView: View {
    @Environment(UsageModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if DemoModeSettings.leads(model) {
                    // Demo mode's only entry point — the dashboard's
                    // disconnected card stays just Connect, so Settings
                    // is the one place to find "View Demo".
                    DemoModeSettings()
                    SettingsGap()
                }
                AppearanceSettings()
                SettingsGap()
                AppIconSettings()
                SettingsGap()
                UsageRowsSettings()
                #if os(iOS)
                SettingsGap()
                GlanceMetricSettings()
                #endif
                if AccountOrderSettings.isOffered(model) {
                    SettingsGap()
                    AccountOrderSettings()
                }
                if AccountListSettings.isOffered(model) {
                    SettingsGap()
                    AccountListSettings()
                }
                if PeakNotificationsSettings.isOffered {
                    SettingsGap()
                    PeakNotificationsSettings()
                }
                SettingsGap()
                BackgroundRefreshSettings()
                SettingsGap()
                ServiceStatusSettings()
                SettingsGap()
                CloudSyncSettings()
                if ExportSettings.isOffered(model) {
                    SettingsGap()
                    ExportSettings()
                }
                SettingsGap()
                PrivacyLinkSettings()
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
            .padding(20)
        }
        .appBackground()
        .navigationTitle("Settings")
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
