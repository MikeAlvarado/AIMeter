#if os(macOS)
import AppKit
import SwiftUI
import UsageKit
import UserNotifications

/// The project's only AppDelegate. SwiftUI exposes no scene-level hook for
/// the activation policy, nor for "the user launched AIMeter while it was
/// already running" — both of which the app needs once its icons can be
/// hidden, since that relaunch becomes the only way back in.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppChrome.terminateOtherInstances()
        // Before launch finishes, so a click on the update notification
        // that launched the app still reaches it.
        UNUserNotificationCenter.current().delegate = AppChrome.notificationRouter
        let prefs = Preferences.load()
        // Applied before first paint so a hidden Dock icon never flashes,
        // and no window opens in the wrong appearance first.
        AppChrome.applyActivationPolicy(hidingDockIcon: prefs.hideDockIcon)
        AppChrome.applyAppearance(prefs.appearance)
        AppChrome.applyAppIcon(prefs.appIcon)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = Preferences.load()
        // The launch refresh starts here, not from the Dashboard's view:
        // that window may not open at all, or close just below, and the
        // schedule's first run is a whole cadence away.
        Task { await AppEnvironment.shared?.refreshAll() }
        // A menu-bar-only app shouldn't greet every launch with a window.
        // `.accessory` alone doesn't suppress the `WindowGroup` (measured —
        // the window is up by the time this runs), so close it deliberately.
        //
        // Only while the status item is present to open one from, though:
        // with both icons hidden the dashboard is the sole affordance the
        // app has left, and suppressing it too would make launching do
        // nothing at all. That combination is the one case where a launch
        // legitimately shows a window.
        // The notch island is such an affordance too (its footer opens the
        // Dashboard), so with it on the window may close as well.
        //
        // The island itself starts next tick, once the scene has handed
        // `AppEnvironment` the preferences it needs (`AIMeterApp`), and
        // `startNotchIslandIfEnabled` is idempotent for the case where the
        // scene got there first.
        DispatchQueue.main.async {
            AppChrome.startNotchIslandIfEnabled()
            AppChrome.updateClaudeSessions()
        }
        // A first launch opens the tour, which shows what is new as well.
        let tourDue = Tour.dueAtLaunch()
        if tourDue {
            AppChrome.openTourWindow()
        }
        AppUpdater.shared.start(automatic: prefs.checksForUpdates, showsNotes: !tourDue)
        #if DEBUG
        IslandDirector.startIfRequested()
        #endif
        #if DEBUG
        if MacSettingsView.launchTab != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                AppChrome.openSettings()
            }
        }
        #endif
        guard prefs.hideDockIcon, prefs.statusItemVisible || prefs.notchIslandEnabled else { return }
        // Next tick, so the scene finishes appearing — and registers its
        // reopen hook — before the window is taken away again.
        DispatchQueue.main.async {
            AppChrome.closeDashboardWindows()
        }
    }

    /// Fires when an already-running AIMeter is launched again (Finder,
    /// Spotlight, `open -a`) — verified to arrive even with no Dock icon and
    /// no status item, which is what makes relaunching a dependable way back
    /// into a fully hidden app.
    ///
    /// It deliberately does *not* clear `hideDockIcon` / `statusItemVisible`:
    /// having to relaunch once shouldn't permanently undo the chrome the
    /// user chose.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        AppChrome.revealMainWindow()
        return true
    }
}

/// Activation-policy and window handling, kept out of the delegate so the
/// Settings toggles can drive the same code paths live.
enum AppChrome {
    /// One AIMeter at a time. Two copies of the app can run side by side
    /// when they live at different paths — the installed one started by
    /// the login item and a build run from Xcode, say — since Launch
    /// Services only refuses a second launch of the *same* bundle. Both
    /// would then refresh the same accounts (rotating the same refresh
    /// tokens against each other), put two islands on the notch, two
    /// status items in the bar, two dashboards on screen. The copy being
    /// launched wins: it is the one the user just asked for.
    static func terminateOtherInstances() {
        // The unit-test host is this same app: a test run must not quit
        // the copy the user has running (the same guard as the island's).
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        where other.processIdentifier != me {
            other.terminate()
        }
    }

    /// `.accessory` drops the Dock icon and the Cmd-Tab entry. The app keeps
    /// running and refreshing either way — this only changes what's visible.
    static func applyActivationPolicy(hidingDockIcon hidden: Bool) {
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
    }

    /// Settings' appearance for every window AppKit draws for the app:
    /// the Dashboard, Settings, alerts, and the menu bar popover — which
    /// `.preferredColorScheme` alone never reached (the `MenuBarExtra`
    /// window kept the system's appearance, so a dark AIMeter opened a
    /// light popover). `.system` clears it back to the system's. Applied
    /// at launch and whenever the setting changes (`AppearanceSettings`);
    /// the notch island draws in a forced dark scheme regardless.
    static func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// The icon picked in Settings, as far as macOS lets an app change its
    /// own: the Dock's and ⌘Tab's picture while AIMeter runs. Finder keeps
    /// the bundle's (Sunset), since rewriting the bundle's icon would break
    /// its code signature. Nil puts the bundle's own back. Applied at
    /// launch, before the Dock shows the app, and whenever the setting
    /// changes (`AppIconSettings`).
    static func applyAppIcon(_ choice: AppIconChoice) {
        NSApp.applicationIconImage = choice.dockImageName.flatMap { NSImage(named: $0) }
    }

    /// Reopens the dashboard scene. Set by that scene the first time it
    /// appears; AppKit callbacks have no access to SwiftUI's environment
    /// actions, so this is the bridge — the same shape as `AppEnvironment`,
    /// which the refresh schedule already relies on.
    static var openDashboard: (() -> Void)?
    /// A Connect sheet to present on the Dashboard: a new account, or a
    /// reconnect of an existing one. Every surface that can't present the
    /// sheet itself — the menu bar popover (a sheet on a `MenuBarExtra`
    /// window renders clipped and floating), the Usage menu — routes
    /// through `connect(_:)`, which reveals the Dashboard and hands it the
    /// request. The Dashboard consumes it from its live hook when it is
    /// already up, else from `onAppear` once the window exists — a request
    /// queued while the window is closed is never lost.
    enum ConnectRequest {
        case add
        case reconnect(ConnectedAccount)
    }

    /// Set by the Dashboard on appear, cleared on disappear, so a stale
    /// closure from a closed window is never called.
    static var presentConnect: ((ConnectRequest) -> Void)?
    static var pendingConnect: ConnectRequest?

    static func connect(_ request: ConnectRequest) {
        pendingConnect = request
        revealMainWindow()
        deliverPendingConnect()
    }

    /// Hands the queued request to the live Dashboard, if there is one.
    static func deliverPendingConnect() {
        guard let request = pendingConnect, let present = presentConnect else { return }
        pendingConnect = nil
        present(request)
    }

    /// One account's Provider Detail, from a surface outside the
    /// Dashboard's navigation (a click on an account in the menu bar
    /// popover). Same bridge shape as `connect(_:)`: the Dashboard window's
    /// navigation stack registers `presentAccount` on appear and clears it
    /// on disappear, and a request made while the window is closed waits in
    /// `pendingAccount` until it appears.
    static var presentAccount: ((String) -> Void)?
    static var pendingAccount: String?

    static func openAccount(_ accountID: String) {
        pendingAccount = accountID
        revealMainWindow()
        deliverPendingAccount()
    }

    static func deliverPendingAccount() {
        guard let accountID = pendingAccount, let present = presentAccount else { return }
        pendingAccount = nil
        present(accountID)
    }

    static func revealMainWindow() {
        closeMenuBarPopover()
        // Prefer an existing window: ordering it front keeps the user's
        // place instead of building a second one beside it.
        if let existing = dashboardWindows.first {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openDashboard?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The menu bar popover's window while it is open, set by the popover
    /// itself (`MenuBarView`, through `WindowReader`).
    static weak var menuBarPopoverWindow: NSWindow?

    /// Closes the menu bar popover. Every route that opens a window of the
    /// app's (the Dashboard, an account, Connect, Settings, the update
    /// window, the tour) calls it first: the popover is not dismissed by a
    /// window of its own app coming forward, so it stayed open over the
    /// window it had just opened, Settings behind it (Mike, 2026-10-21;
    /// the island had the same bug and closes itself on the way).
    ///
    /// It is closed through SwiftUI's own `dismiss`, which the popover
    /// hands over on appear (`dismissMenuBarPopover`): `close()` on its
    /// window put it away but left the status item thinking it was open,
    /// so the next click only "closed" it again and it took two to open
    /// (measured on macOS 27).
    static func closeMenuBarPopover() {
        guard let window = menuBarPopoverWindow, window.isVisible else { return }
        if let dismissMenuBarPopover {
            dismissMenuBarPopover()
        } else {
            window.close()
        }
    }

    /// The popover's `dismiss` action, set by `MenuBarView` on appear.
    static var dismissMenuBarPopover: (() -> Void)?

    static func closeDashboardWindows() {
        dashboardWindows.forEach { $0.close() }
    }

    /// Opens the Settings scene from a surface outside the scene graph
    /// (the notch island). The dashboard scene publishes SwiftUI's
    /// `openSettings` action here on appear, like `openDashboard`; the
    /// selector is the fallback for a call that lands before it has.
    static var openSettingsAction: (() -> Void)?

    static func openSettings() {
        closeMenuBarPopover()
        if let openSettingsAction {
            openSettingsAction()
        } else {
            _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Updates

    /// Opens the update window (`AIMeterApp.updateWindowID`). The dashboard
    /// scene publishes SwiftUI's `openWindow` here on appear; a request
    /// made before that (the notes after a manual update, at launch) waits
    /// in `pendingUpdateWindow` for it.
    static var openUpdateWindowAction: (() -> Void)?
    static var pendingUpdateWindow = false

    static func openUpdateWindow() {
        if let openUpdateWindowAction {
            closeMenuBarPopover()
            openUpdateWindowAction()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            pendingUpdateWindow = true
        }
    }

    static func deliverPendingUpdateWindow() {
        guard pendingUpdateWindow else { return }
        pendingUpdateWindow = false
        openUpdateWindow()
    }

    /// Closed before the restart, so window restoration doesn't bring it
    /// back over the new version.
    static func closeUpdateWindow() {
        NSApp.windows
            .filter { $0.identifier?.rawValue.hasPrefix(AIMeterApp.updateWindowID) == true }
            .forEach { $0.close() }
    }

    // MARK: Tour

    /// Opens the tour's window (`AIMeterApp.tourWindowID`): at the first
    /// launch, and from Settings. The same bridge as the update window's:
    /// the dashboard scene publishes `openWindow` here on appear, and a
    /// request made before that waits in `pendingTourWindow`.
    static var openTourWindowAction: (() -> Void)?
    static var pendingTourWindow = false

    static func openTourWindow() {
        if let openTourWindowAction {
            closeMenuBarPopover()
            openTourWindowAction()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            pendingTourWindow = true
        }
    }

    static func deliverPendingTourWindow() {
        guard pendingTourWindow else { return }
        pendingTourWindow = false
        openTourWindow()
    }

    static let notificationRouter = NotificationRouter()

    // MARK: Notch island

    /// The one island (see "macOS notch island" in `AIMeter/CLAUDE.md`).
    /// Started at launch and by the Settings toggle; both read the live
    /// model and preferences through `AppEnvironment`.
    static let notchIsland = NotchIslandController()

    static func startNotchIslandIfEnabled() {
        // The unit-test host is this app: it must not put a panel on the
        // tester's notch (nor race the tests with a reveal).
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard let model = AppEnvironment.shared, let prefs = AppEnvironment.prefs, prefs.notchIslandEnabled else { return }
        notchIsland.start(model: model, prefs: prefs)
    }

    /// Settings' toggle: show or remove the island live. The preference
    /// itself (and its coupling with the status item) is written by
    /// `PreferencesModel.setNotchIsland(enabled:)`; this is the chrome.
    static func setNotchIsland(enabled: Bool) {
        if enabled {
            startNotchIslandIfEnabled()
        } else {
            notchIsland.stop()
        }
        updateClaudeSessions()
    }

    // MARK: Claude Code sessions

    /// Starts or stops the session monitor (see "Claude Code sessions" in
    /// the repo-root CLAUDE.md): it runs while the island shows sessions
    /// (the island on, and "Show sessions in the notch" on) or while the
    /// "done" notification is on. Called at launch, by the island's switch
    /// and by the Claude Code tab's.
    static func updateClaudeSessions() {
        guard let prefs = AppEnvironment.prefs else { return }
        let shows = prefs.notchIslandEnabled && prefs.claudeSessionsEnabled
        ClaudeSessionMonitor.shared.update(enabled: shows || prefs.claudeSessionsNotify, notifies: prefs.claudeSessionsNotify)
    }

    /// Windows belonging to the dashboard scene, matched on the identifier
    /// SwiftUI derives from `WindowGroup(id:)` ("dashboard-AppWindow-1").
    /// Matching on that rather than "any main-capable window" keeps the
    /// Settings window — which is also main-capable — out of it.
    private static var dashboardWindows: [NSWindow] {
        NSApp.windows.filter {
            $0.identifier?.rawValue.hasPrefix(AIMeterApp.dashboardWindowID) == true
        }
    }
}
/// Routes a click on the update notification to the update window, and
/// lets that one notification show while AIMeter is in front. Every other
/// notification keeps the system's default (not shown in front).
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier.hasPrefix(AppUpdater.notificationPrefix) else { return }
        await MainActor.run { AppChrome.openUpdateWindow() }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.identifier.hasPrefix(AppUpdater.notificationPrefix) ? [.banner, .list] : []
    }
}
#endif
