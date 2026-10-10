#if os(macOS)
import AppKit

/// The pointer half of the controller, for a screen without a notch, and
/// the options that only matter there: hidden until hovered, hidden
/// behind a full-screen app, and left out of screen captures.
///
/// On a screen without a notch the island tracks the pointer itself
/// instead of trusting SwiftUI's hover: a hidden island has no pixels for
/// the window server to route the mouse to, and the pill's gap above it
/// is transparent, so `onHover` would never fire where the user aims. A
/// global `mouseMoved` monitor (mouse monitors need no permission, unlike
/// keyboard ones) answers "is the pointer on the island's place or on
/// what is drawn now" geometrically, on every move and only on a move —
/// nothing runs while the mouse is still. While AIMeter itself is
/// frontmost the global monitor hears nothing, so that stretch is
/// polled instead (`updateActivePolling`).
extension NotchIslandController {
    /// Whether this controller, not SwiftUI, is the hover source.
    var tracksPointer: Bool { !pointerMonitors.isEmpty }

    /// Tracks the pointer exactly while the island is on a screen without
    /// a notch.
    func updatePointerTracking() {
        if isRunning, screen != nil, state.mode.drawsOwnShape {
            installPointerMonitors()
        } else {
            removePointerMonitors()
        }
        updateActivePolling()
    }

    private func installPointerMonitors() {
        guard pointerMonitors.isEmpty else { return }
        // A hover SwiftUI reported before the switch would never get its
        // leave from SwiftUI again; start from "outside" and let the next
        // move say where the pointer is.
        if interaction.isInside { handle(.left) }
        pointerInside = false
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            Task { @MainActor [weak self] in self?.pointerMoved() }
        }) {
            pointerMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            Task { @MainActor [weak self] in self?.pointerMoved() }
            return event
        }) {
            pointerMonitors.append(local)
        }
        pointerMoved()
    }

    func removePointerMonitors() {
        guard !pointerMonitors.isEmpty else { return }
        pointerMonitors.forEach { NSEvent.removeMonitor($0) }
        pointerMonitors.removeAll()
        activePollTask?.cancel()
        activePollTask = nil
        if pointerInside {
            pointerInside = false
            handle(.left)
        }
    }

    /// One pointer position against the island's collapsed place and its
    /// drawn slab; only a change of side reaches the interaction.
    func pointerMoved(to location: NSPoint = NSEvent.mouseLocation) {
        guard tracksPointer, let screen else { return }
        let region = NotchIslandGeometry.hoverRegion(screen, mode: state.mode, options: options, rowWidth: rowWidth)
        let slab = state.isConcealed ? .zero : slabOnScreen()
        let inside = NotchIslandVisibility.pointerIsInside(location, region: region, slab: slab)
        guard inside != pointerInside else { return }
        pointerInside = inside
        handle(inside ? .entered : .left)
    }

    /// The slab as drawn now, in screen coordinates (the hosting view
    /// fills the panel; the slab is reported top-left based).
    private func slabOnScreen() -> CGRect {
        guard let panel, let hosting, hosting.slab != .zero else { return .zero }
        let slab = hosting.slab
        return CGRect(x: panel.frame.minX + slab.minX, y: panel.frame.maxY - slab.maxY, width: slab.width, height: slab.height)
    }

    /// While AIMeter is the active app (its Dashboard or Settings in
    /// front) the global monitor is silent and the local one only hears
    /// moves over AIMeter's own windows, so the pointer is polled — 20
    /// times a second, and only for as long as that lasts.
    func updateActivePolling() {
        let wanted = tracksPointer && NSApp.isActive
        guard wanted != (activePollTask != nil) else { return }
        if !wanted {
            activePollTask?.cancel()
            activePollTask = nil
            return
        }
        activePollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.pointerMoved()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    // MARK: - Concealment

    /// Puts the island out of sight, or back, per `NotchIslandVisibility`;
    /// the view slides it on the level spring. Once it has moved, the
    /// window server's mouse shape is resampled, so a hidden island stops
    /// catching clicks on the menu bar where it was.
    func updateConcealment() {
        let concealed = NotchIslandVisibility.isConcealed(
            mode: state.mode,
            level: interaction.level,
            isRevealing: state.isRevealing,
            hidesUntilHover: prefs?.notchIslandHidesUntilHover ?? false,
            hidesInFullScreen: prefs?.notchIslandHidesInFullScreen ?? true,
            isFullScreen: isFullScreen,
            pointerInside: tracksPointer && interaction.isInside,
            peeksOnHover: prefs?.notchIslandExpandsOnHover ?? true
        )
        guard state.isConcealed != concealed else { return }
        state.isConcealed = concealed
        scheduleSettle()
    }

    // MARK: - Full screen

    /// Checks now and again as a Space switch settles: the notification
    /// can arrive before the full-screen window is on screen.
    func scheduleFullScreenChecks() {
        fullScreenTask?.cancel()
        checkFullScreen()
        fullScreenTask = Task { @MainActor [weak self] in
            // Again at 0.4 s and at 1.2 s.
            for delay in [400, 800] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                self?.checkFullScreen()
            }
        }
    }

    /// Whether a full-screen app has the island's screen, from the
    /// on-screen window list (`NotchIslandVisibility.isFullScreen`). Only
    /// asked where it matters: a screen without a notch, with the option on.
    private func checkFullScreen() {
        guard isRunning, state.mode.drawsOwnShape, prefs?.notchIslandHidesInFullScreen ?? true, let displayID else {
            setFullScreen(false)
            return
        }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = info.compactMap { window -> NotchIslandVisibility.Window? in
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return NotchIslandVisibility.Window(layer: layer, bounds: rect)
        }
        setFullScreen(NotchIslandVisibility.isFullScreen(display: CGDisplayBounds(displayID), windows: windows))
    }

    private func setFullScreen(_ value: Bool) {
        guard isFullScreen != value else { return }
        isFullScreen = value
        updateConcealment()
        // Only while it holds the island hidden: a slow re-check, so an
        // app that leaves its own full screen without a Space change or an
        // app switch doesn't leave the island hidden on the desktop.
        fullScreenWatchTask?.cancel()
        fullScreenWatchTask = nil
        guard value else { return }
        fullScreenWatchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.checkFullScreen()
            }
        }
    }

    // MARK: - Preferences

    /// Screenshots and screen recordings leave the panel out when asked:
    /// `sharingType = .none` (verified against `screencapture` on macOS
    /// 27; `.readOnly` is every window's default).
    func applyCapturePolicy() {
        let hidden = prefs?.notchIslandHiddenFromCapture ?? false
        panel?.sharingType = hidden ? .none : .readOnly
    }

    /// Re-applies whatever the island's options shape, whenever the
    /// preferences change. `PreferencesModel` keeps one stored value, so
    /// any preference wakes this; everything it calls is idempotent.
    func observePreferences() {
        guard let prefs else { return }
        withObservationTracking {
            _ = prefs.notchIslandOptions
            _ = prefs.notchIslandHidesUntilHover
            _ = prefs.notchIslandHidesInFullScreen
            _ = prefs.notchIslandHiddenFromCapture
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.preferencesChanged()
                self.observePreferences()
            }
        }
    }

    private func preferencesChanged() {
        applyCapturePolicy()
        relocate()
        updateConcealment()
    }
}
#endif
