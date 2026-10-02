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
            await UsageModel.refreshAllInBackground()
        }
        #endif
        #if os(macOS)
        // A "Usage" menu so the shortcuts are discoverable, not just
        // memorized. ⌘R lives here (and in the popover, which has no main
        // menu); the Dashboard's refresh button no longer declares its own.
        .commands {
            CommandMenu("Usage") {
                Button("Refresh All") {
                    Task { await model.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isRefreshing || model.isDemoMode)

                Button("Add Account…") {
                    AppChrome.revealMainWindow()
                    AppChrome.requestAddAccount?()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.isDemoMode)

                Divider()

                Button(prefs.displayMode == .used ? "Show Remaining" : "Show Used") {
                    prefs.displayMode = prefs.displayMode == .used ? .remaining : .used
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Button(prefs.resetStyle == .relative ? "Absolute Reset Times" : "Relative Reset Times") {
                    prefs.toggleResetStyle()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
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
            // The countdown style ticks: nothing else in the label changes
            // between fetches, so only then is the label re-evaluated on a
            // clock (once a minute, the countdown's own resolution).
            if prefs.menuBarShowsResetCountdown {
                TimelineView(.everyMinute) { context in
                    MenuBarLabel(model: .current(model: model, prefs: prefs, now: context.date))
                }
            } else {
                MenuBarLabel(model: .current(model: model, prefs: prefs))
            }
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
