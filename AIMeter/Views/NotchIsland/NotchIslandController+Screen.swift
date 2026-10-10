#if os(macOS)
import AppKit

/// The screen half of the controller: which display hosts the island,
/// how it is described to the pure geometry, the panel's one frame, and
/// the observers that revalidate it.
extension NotchIslandController {
    // MARK: - Screen

    /// Picks the screen again and sets the panel's one frame: on start,
    /// when displays change, after wake, and on a Space change (the panel
    /// is on every Space, but its frame is revalidated).
    func relocate() {
        guard let panel else { return }
        let screens = NSScreen.screens.map(Self.describe)
        guard let index = NotchIslandGeometry.target(screens: screens) else {
            panel.orderOut(nil)
            screen = nil
            return
        }
        let changed = screen != screens[index]
        screen = screens[index]
        let mode = NotchIslandGeometry.mode(for: screens[index])
        let closed = NotchIslandGeometry.closedSize(screens[index], mode: mode)
        if state.mode != mode { state.mode = mode }
        if state.barHeight != closed.height { state.barHeight = closed.height }
        if state.closedWidth != closed.width { state.closedWidth = closed.width }
        guard changed || !panel.isVisible else { return }
        // Laid out and drawn before it is shown: the window server samples
        // which pixels take the mouse when a window appears. SwiftUI may
        // still draw on a later turn, so the first slab report resamples
        // once more (`slabChanged` → `resampleMouseShape`).
        panel.setFrame(NotchIslandGeometry.windowFrame(screens[index], mode: mode), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        if isRunning { panel.orderFrontRegardless() }
        scheduleSettle()
    }

    /// An `NSScreen` as the pure geometry reads it. Without a notch the
    /// menu bar's height is what `visibleFrame` leaves out at the top.
    static func describe(_ screen: NSScreen) -> NotchIslandGeometry.Screen {
        let safeTop = screen.safeAreaInsets.top
        var auxLeft = screen.auxiliaryTopLeftArea
        var auxRight = screen.auxiliaryTopRightArea
        #if DEBUG
        // `-AIMeterForcePill YES` tries the pill on a Mac with a notch.
        if UserDefaults.standard.bool(forKey: "AIMeterForcePill") {
            auxLeft = nil
            auxRight = nil
        }
        #endif
        let hasNotch = safeTop > 0 && auxLeft != nil && auxRight != nil
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchIslandGeometry.Screen(
            frame: screen.frame,
            safeTop: hasNotch ? safeTop : max(menuBar, NSStatusBar.system.thickness),
            auxLeft: hasNotch ? auxLeft : nil,
            auxRight: hasNotch ? auxRight : nil
        )
    }

    func observe() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let relocate: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.relocate() }
        }
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: relocate)))
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: relocate)))
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: relocate)))
    }
}
#endif
