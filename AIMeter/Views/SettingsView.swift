import SwiftUI
import UsageKit

/// Settings on iOS: one screen (Mike's reorganization, 2026-10-22).
/// The accounts first, inline, since they are what people come for (each
/// row opens its page, which holds that account's notifications; "Add
/// account" opens the Connect sheet over Settings; "Order by urgency"
/// under them), then one row per group, each opening its own screen:
/// Appearance, Widgets, Refresh & data, About. No Notifications group:
/// every alert is an account's, so it would only have listed the accounts
/// above again (Mike, 2026-10-22). While nothing is connected, or while the demo is on, the
/// demo's card leads. The Mac's Settings window has the same groups as
/// tabs and sections (`MacSettingsView`); both are built from the section
/// views in `SettingsSections.swift`.
struct SettingsView: View {
    @Environment(UsageModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if DemoModeSettings.leads(model) {
                    // Demo mode's only entry point: the dashboard's
                    // disconnected card stays just Connect, so Settings
                    // is the one place to find "View Demo".
                    DemoModeSettings()
                    SettingsGap()
                }
                AccountListSettings()
                SettingsGap()
                if PeakNotificationsSettings.isOffered {
                    PeakNotificationsSettings()
                    SettingsGap()
                }
                Card {
                    VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                        SettingsGroupLink(title: String(localized: "Appearance"), symbol: "paintbrush") {
                            AppearanceSettings()
                            SettingsGap()
                            AppIconSettings()
                            if UsageRowsSettings.isOffered(model) {
                                SettingsGap()
                                UsageRowsSettings()
                            }
                        }
                        Divider().overlay(Theme.track)
                        #if os(iOS)
                        SettingsGroupLink(title: String(localized: "Widgets"), symbol: "square.grid.2x2") {
                            GlanceMetricSettings()
                            SettingsGap()
                            WidgetHowToSettings()
                        }
                        Divider().overlay(Theme.track)
                        #endif
                        SettingsGroupLink(title: String(localized: "Refresh & data"), symbol: "arrow.clockwise") {
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
                        }
                        Divider().overlay(Theme.track)
                        SettingsGroupLink(title: String(localized: "About"), symbol: "info.circle") {
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
                    }
                }
            }
            .padding(20)
        }
        .appBackground()
        .navigationTitle("Settings")
    }
}

/// One group's row on the iOS Settings screen: its symbol on the wash,
/// its name, a chevron, opening a screen of its sections.
private struct SettingsGroupLink<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationLink {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content()
                }
                .padding(20)
            }
            .appBackground()
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(verbatim: title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if os(iOS)
/// Widgets: how to put one on the Home Screen or the Lock Screen, since
/// the app can't place them itself.
private struct WidgetHowToSettings: View {
    var body: some View {
        SectionHeader(title: String(localized: "Add a widget"))
        Card {
            Text("Touch and hold your Home Screen or Lock Screen, tap Edit, then Add Widget, and search for AIMeter. Each widget can show any of your accounts: touch and hold it, then Edit Widget.")
                .font(.callout)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif

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
