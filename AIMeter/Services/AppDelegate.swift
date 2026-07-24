#if os(macOS)
import AppKit
import SwiftUI

/// The project's only AppDelegate. SwiftUI exposes no scene-level hook for
/// the activation policy, nor for "the user launched AIMeter while it was
/// already running" — both of which the app needs once its icons can be
/// hidden, since that relaunch becomes the only way back in.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
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
        guard prefs.hideDockIcon, prefs.statusItemVisible else { return }
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
