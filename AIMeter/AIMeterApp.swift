import SwiftUI
import UsageKit

@main
struct AIMeterApp: App {
    @State private var model = UsageModel()
    @State private var prefs = PreferencesModel()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some Scene {
        WindowGroup(id: Self.dashboardWindowID) {
            ContentView()
                .environment(model)
                .environment(prefs)
                .tint(Theme.accent)
                .preferredColorScheme(prefs.appearance.colorScheme)
                #if os(macOS)
                // Hands the delegate a way to reopen this scene from a plain
                // AppKit callback, which has no access to SwiftUI's
                // environment actions.
                .onAppear {
                    AppChrome.openDashboard = { openWindow(id: Self.dashboardWindowID) }
                }
                #endif
        }
        #if os(iOS)
        .backgroundTask(.appRefresh(AppConfig.refreshTaskID)) {
            await BackgroundRefresh.scheduleNext()
            _ = try? await RefreshService().refresh()
        }
        #endif

        #if os(macOS)
        MenuBarExtra(isInserted: $prefs.statusItemVisible) {
            MenuBarView()
                .environment(model)
                .environment(prefs)
                .tint(Theme.accent)
                .preferredColorScheme(prefs.appearance.colorScheme)
        } label: {
            MenuBarLabel(
                snapshot: model.snapshot,
                displayMode: prefs.displayMode,
                metric: prefs.glanceMetric,
                showsPercentage: prefs.menuBarShowsPercentage
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            NavigationStack {
                SettingsView()
            }
            .environment(model)
            .environment(prefs)
            .tint(Theme.accent)
            .preferredColorScheme(prefs.appearance.colorScheme)
            .frame(minWidth: 440, minHeight: 560)
        }
        #endif
    }

    /// Identifies the dashboard scene so the macOS AppDelegate can reopen it
    /// by id after both icons have been hidden.
    static let dashboardWindowID = "dashboard"
}
