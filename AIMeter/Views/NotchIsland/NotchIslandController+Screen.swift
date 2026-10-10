#if os(macOS)
import AppKit

/// The screen half of the controller: which display hosts the island,
/// how it is described to the pure geometry, the panel's one frame, and
/// the observers that revalidate it.
extension NotchIslandController {
    // MARK: - Screen

    /// Picks the screen again and sets the panel's one frame: on start,
    /// when displays change, after wake, on a Space change (the panel is
    /// on every Space, but its frame is revalidated) and when an option
    /// that shapes it changes (`preferencesChanged`).
    func relocate() {
        guard let panel else { return }
        let nsScreens = NSScreen.screens
        let screens = nsScreens.map(Self.describe)
        guard let index = NotchIslandGeometry.target(screens: screens) else {
            panel.orderOut(nil)
            screen = nil
            displayID = nil
            updatePointerTracking()
            return
        }
        let described = screens[index]
        let options = prefs?.notchIslandOptions ?? NotchIslandGeometry.Options()
        let mode = NotchIslandGeometry.mode(for: described, form: options.form)
        let frame = NotchIslandGeometry.windowFrame(described, mode: mode, options: options)
        let changed = screen != described || self.options != options || panel.frame != frame
        screen = described
        self.options = options
        displayID = nsScreens[index].deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let closed = NotchIslandGeometry.closedSize(described, mode: mode, options: options)
        let topInset = NotchIslandGeometry.topInset(described, mode: mode, options: options)
        let rowScale = NotchIslandGeometry.rowScale(described, mode: mode, options: options)
        if state.mode != mode { state.mode = mode }
        if state.barHeight != closed.height { state.barHeight = closed.height }
        if state.closedWidth != closed.width { state.closedWidth = closed.width }
        if state.topInset != topInset { state.topInset = topInset }
        if state.rowScale != rowScale { state.rowScale = rowScale }
        // A new screen or form can make the island concealable or not —
        // at launch, after a display change, after the lid opens onto a
        // real notch (which must never stay hidden).
        updateConcealment()
        updatePointerTracking()
        scheduleFullScreenChecks()
        guard changed || !panel.isVisible else { return }
        // Laid out and drawn before it is shown: the window server samples
        // which pixels take the mouse when a window appears. SwiftUI may
        // still draw on a later turn, so the first slab report resamples
        // once more (`slabChanged` → `resampleMouseShape`).
        panel.setFrame(frame, display: false)
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
        // `-AIMeterForceDrawnNotch YES` tries the drawn shapes (notch or
        // pill, per the setting) on a Mac with a real notch.
        if UserDefaults.standard.bool(forKey: "AIMeterForceDrawnNotch") {
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
        // A full-screen app comes and goes with a Space change (above) or
        // an app switch, which can bring a full-screen Space forward.
        let fullScreen: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleFullScreenChecks() }
        }
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: fullScreen)))
        // While AIMeter itself is frontmost the global pointer monitor
        // hears nothing, so the pointer is polled for that stretch.
        let activity: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateActivePolling() }
        }
        observers.append((center, center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: activity)))
        observers.append((center, center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: activity)))
    }
}
#endif
