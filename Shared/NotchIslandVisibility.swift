import CoreGraphics

/// When the collapsed island steps out of sight on a screen without a
/// notch, and how a full-screen app is recognized there — pure, so both
/// rules are tested rather than eyeballed. A screen with a notch never
/// conceals anything: collapsed, the island already *is* the notch.
enum NotchIslandVisibility {
    /// One on-screen window as `CGWindowListCopyWindowInfo` reports it:
    /// its level and its bounds in global display coordinates (top-left
    /// origin, the same space as `CGDisplayBounds`). Neither needs the
    /// Screen Recording permission — only window *names* do.
    struct Window: Equatable {
        var layer: Int
        var bounds: CGRect
    }

    /// Whether a full-screen app has the display: a normal-level window
    /// (layer 0) that starts at the display's top edge and runs its whole
    /// height — over the menu bar's strip, where no ordinary window goes.
    /// That is a full-screen app (exactly the display's size), each half
    /// of a Split View, and a game's borderless "windowed full screen".
    /// Measured on macOS 27: in a full-screen Space the menu bar's window
    /// is gone and the app's window is the display's size; on an ordinary
    /// desktop every normal window starts below the bar, and the
    /// full-size Dock window sits at its own level (20). Narrower than a
    /// quarter of the display doesn't count (an overlay, a palette).
    /// Public API, no permission — the signals that look made for this
    /// (`currentSystemPresentationOptions`, `NSMenu.menuBarVisible()`,
    /// `visibleFrame`) report another app's full screen as nothing at
    /// all, from an accessory app.
    static func isFullScreen(display: CGRect, windows: [Window]) -> Bool {
        guard !display.isEmpty else { return false }
        return windows.contains { window in
            window.layer == 0
                && abs(window.bounds.minY - display.minY) <= 1
                && window.bounds.height >= display.height - 1
                && window.bounds.width >= display.width / 4
                && window.bounds.minX >= display.minX - 1
                && window.bounds.maxX <= display.maxX + 1
        }
    }

    /// Whether the island is out of sight right now. Only a drawn shape
    /// (no notch), only while collapsed and not showing the first-run
    /// reveal: once the cursor has opened it, it stays until it closes.
    /// "Hide until hovered" conceals it always; "Hide in full screen"
    /// only while a full-screen app has the screen — there is no menu
    /// bar to sit in then, and it would cover the app. With "Peek on
    /// hover" off nothing ever opens on hover, so the pointer on the
    /// island's place reveals the row by itself — otherwise a hidden
    /// island would have no pixels to click and no way back.
    static func isConcealed(
        mode: NotchIslandGeometry.Mode,
        level: NotchIslandInteraction.Level,
        isRevealing: Bool,
        hidesUntilHover: Bool,
        hidesInFullScreen: Bool,
        isFullScreen: Bool,
        pointerInside: Bool = false,
        peeksOnHover: Bool = true
    ) -> Bool {
        guard mode.drawsOwnShape, level == .collapsed, !isRevealing else { return false }
        if pointerInside, !peeksOnHover { return false }
        return hidesUntilHover || (hidesInFullScreen && isFullScreen)
    }

    /// Whether the pointer is on the island, on a screen without a notch:
    /// on its collapsed place (`NotchIslandGeometry.hoverRegion`, which
    /// stays live while the island is hidden) or on the slab as it is
    /// drawn now (the open island), both in screen coordinates. The top
    /// edge counts: a pointer pushed against the top of the screen reads
    /// exactly the screen's `maxY` in AppKit's coordinates, which
    /// `CGRect.contains` leaves out — flicking the cursor up would start
    /// the dwell on the way and cancel it on arrival.
    static func pointerIsInside(_ point: CGPoint, region: CGRect, slab: CGRect) -> Bool {
        containsWithTopEdge(region, point) || (!slab.isEmpty && containsWithTopEdge(slab, point))
    }

    private static func containsWithTopEdge(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x < rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}
