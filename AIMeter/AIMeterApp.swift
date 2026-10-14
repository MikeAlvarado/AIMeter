import SwiftUI
import UsageKit

@main
struct AIMeterApp: App {
    @State private var model = UsageModel()
    @State private var prefs = PreferencesModel()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Ticks the status item's reset countdown once a minute — see
    /// `MinuteClock` for why this is not a `TimelineView`.
    @State private var minuteClock = MinuteClock()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
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
                .environment(AppUpdater.shared)
                .onAppear {
                    AppChrome.openDashboard = { openWindow(id: Self.dashboardWindowID) }
                    AppChrome.openSettingsAction = { openSettings() }
                    AppChrome.openUpdateWindowAction = { openWindow(id: Self.updateWindowID) }
                    AppChrome.deliverPendingUpdateWindow()
                    // The notch island lives outside the scene graph; this
                    // is where it gets the app's one `PreferencesModel`.
                    AppEnvironment.prefs = prefs
                    AppChrome.startNotchIslandIfEnabled()
                    AppChrome.updateClaudeSessions()
                }
                #endif
        }
        #if os(macOS)
        // Tall enough for two accounts and the Claude Code section; the
        // content's own minimum (`ContentView`) holds a restored window.
        .defaultSize(width: 460, height: 760)
        #endif
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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    AppChrome.openUpdateWindow()
                    Task { await AppUpdater.shared.check(userInitiated: true) }
                }
                .disabled(!AppUpdater.shared.isAvailable)
            }
            CommandMenu("Usage") {
                Button("Refresh All") {
                    Task { await model.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isRefreshing || model.isDemoMode)

                Button("Add Account…") {
                    AppChrome.connect(.add)
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
                .environment(AppUpdater.shared)
                .tint(Theme.accent)
                .preferredColorScheme(prefs.appearance.colorScheme)
        } label: {
            // The countdown style ticks: nothing else in the label changes
            // between fetches, so only then does the label read the clock
            // (once a minute, the countdown's own resolution). Never a
            // `TimelineView` here — see `MinuteClock`.
            MenuBarLabel(model: .current(
                model: model, prefs: prefs,
                now: prefs.menuBarShowsResetCountdown ? minuteClock.now : Date()
            ))
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView()
                .environment(model)
                .environment(prefs)
                .environment(AppUpdater.shared)
                .tint(Theme.accent)
                .preferredColorScheme(prefs.appearance.colorScheme)
        }

        // The update notice: the new version's notes with Restart to
        // Update, or this version's notes after a manual install.
        Window(String(localized: "Software Update"), id: Self.updateWindowID) {
            UpdateWindow()
                .environment(AppUpdater.shared)
                .tint(Theme.accent)
                .preferredColorScheme(prefs.appearance.colorScheme)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        #endif
    }

    /// Identifies the dashboard scene so the macOS AppDelegate can reopen it
    /// by id after both icons have been hidden.
    static let dashboardWindowID = "dashboard"
    /// The macOS update window (`UpdateWindow`).
    static let updateWindowID = "update"
}
