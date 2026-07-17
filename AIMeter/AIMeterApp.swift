import SwiftUI
import UsageKit

@main
struct AIMeterApp: App {
    @State private var model = UsageModel()
    @State private var prefs = PreferencesModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(prefs)
                .tint(Theme.accent)
                .preferredColorScheme(prefs.appearance.colorScheme)
        }
        #if os(iOS)
        .backgroundTask(.appRefresh(AppConfig.refreshTaskID)) {
            await BackgroundRefresh.scheduleNext()
            _ = try? await RefreshService().refresh()
        }
        #endif

        #if os(macOS)
        MenuBarExtra {
            MenuBarView()
                .environment(model)
                .environment(prefs)
                .tint(Theme.accent)
                .preferredColorScheme(prefs.appearance.colorScheme)
        } label: {
            MenuBarLabel(snapshot: model.snapshot, displayMode: prefs.displayMode)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(prefs)
                .tint(Theme.accent)
                .preferredColorScheme(prefs.appearance.colorScheme)
                .frame(minWidth: 440, minHeight: 560)
        }
        #endif
    }
}
