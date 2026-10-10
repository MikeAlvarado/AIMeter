#if os(macOS)
import AppKit
import SwiftUI
import UsageKit

/// The project's only AppDelegate. SwiftUI exposes no scene-level hook for
/// the activation policy, nor for "the user launched AIMeter while it was
/// already running" — both of which the app needs once its icons can be
/// hidden, since that relaunch becomes the only way back in.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppChrome.terminateOtherInstances()
        // Applied before first paint so a hidden Dock icon never flashes.
        AppChrome.applyActivationPolicy(hidingDockIcon: Preferences.load().hideDockIcon)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = Preferences.load()
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
        }
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
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
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

    static func revealMainWindow() {
        // Prefer an existing window: ordering it front keeps the user's
        // place instead of building a second one beside it.
        if let existing = dashboardWindows.first {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openDashboard?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    static func closeDashboardWindows() {
        dashboardWindows.forEach { $0.close() }
    }

    /// Opens the Settings scene from a surface outside the scene graph
    /// (the notch island). The dashboard scene publishes SwiftUI's
    /// `openSettings` action here on appear, like `openDashboard`; the
    /// selector is the fallback for a call that lands before it has.
    static var openSettingsAction: (() -> Void)?

    static func openSettings() {
        if let openSettingsAction {
            openSettingsAction()
        } else {
            _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

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
#endif
