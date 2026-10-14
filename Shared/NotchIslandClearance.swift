import CoreGraphics

/// How far the wings beside a real notch may reach without covering the
/// menu bar's own items (see "Claude Code sessions" in the repo-root
/// CLAUDE.md): the status items on the right, and the open app's menu
/// titles on the left. On a screen without a notch the same room is
/// measured from the line down the screen's centre (`anchor`), which the
/// drawn notch and the pill are centred on, so a "wing" there is half
/// their row. Up to macOS 26 each status item is a window whose frame the
/// public window list gives with no permission; on macOS 27 they are all
/// drawn by `MenuBarAgent` and only the Accessibility API places them, as
/// it does the menus. The wings keep one width, so the narrower side sets
/// both. Pure: the controller reads the window list and the Accessibility
/// frames (`NotchIslandController+Clearance.swift`).
enum NotchIslandClearance {
    /// A window from the on-screen window list: its frame in global
    /// coordinates (top-left origin, so its x is AppKit's x) and its level.
    struct Window: Equatable {
        let frame: CGRect
        let layer: Int
    }

    /// `kCGStatusWindowLevel`: the level of every status item's window.
    static let statusItemLayer = 25
    /// Air left between the slab and the nearest item it spares.
    static let margin: CGFloat = 6

    /// The left edge of the status items right of the notch, on the
    /// island's menu bar (`menuBarTop` is that bar's top in the window
    /// list's coordinates); nil with none there.
    static func statusItemsMinX(_ windows: [Window], notch: CGRect, menuBarTop: CGFloat, menuBarHeight: CGFloat) -> CGFloat? {
        windows
            .filter { window in
                window.layer == statusItemLayer
                    && abs(window.frame.minY - menuBarTop) < 2
                    && window.frame.height <= menuBarHeight + 2
                    && window.frame.width > 0
                    && window.frame.minX >= notch.maxX - 1
            }
            .map(\.frame.minX)
            .min()
    }

    /// The same edge from the status items' own frames, as the
    /// Accessibility API reports them (each app's "extras" menu bar).
    /// Those sit inside the bar rather than spanning it (a few points
    /// below its top, measured on macOS 27), so an item counts when its
    /// middle is on the island's bar.
    static func statusItemsMinX(items: [CGRect], notch: CGRect, menuBarTop: CGFloat, menuBarHeight: CGFloat) -> CGFloat? {
        items
            .filter { item in
                item.width > 0 && item.height > 0
                    && item.midY > menuBarTop && item.midY < menuBarTop + menuBarHeight + 2
                    && item.minX >= notch.maxX - 1
            }
            .map(\.minX)
            .min()
    }

    /// The right edge of the open app's menu titles left of the notch (the
    /// frames the Accessibility API reports for its menu bar's items); nil
    /// with none there.
    static func menusMaxX(_ items: [CGRect], notch: CGRect) -> CGFloat? {
        items
            .filter { $0.width > 0 && $0.minX < notch.minX }
            .map { min($0.maxX, notch.minX) }
            .max()
    }

    /// The widest a wing may be: from the notch (or the centre line,
    /// `anchor`) to the nearest item on either side, less the slab's ear
    /// beyond the wing (`ear`) and `margin`; nil when nothing is known on
    /// either side.
    static func availableWing(notch: CGRect, menusMaxX: CGFloat?, statusItemsMinX: CGFloat?, ear: CGFloat) -> CGFloat? {
        let spaces = [menusMaxX.map { notch.minX - $0 }, statusItemsMinX.map { $0 - notch.maxX }].compactMap { $0 }
        return spaces.min().map { max(0, $0 - ear - margin) }
    }

    /// What the room is measured from: the notch, or on a screen without
    /// one the line down its centre, the menu bar tall, which the drawn
    /// row is centred on. In AppKit's coordinates, like the notch.
    static func anchor(mode: NotchIslandGeometry.Mode, screen: NotchIslandGeometry.Screen) -> CGRect {
        if case .notch(let notch) = mode { return notch }
        return CGRect(x: screen.frame.midX, y: screen.frame.maxY - screen.safeTop, width: 0, height: screen.safeTop)
    }

    /// How far the collapsed slab reaches past its content on each side:
    /// a notch's ear, real or drawn, or the closed pill's inset.
    static func ear(mode: NotchIslandGeometry.Mode, barHeight: CGFloat) -> CGFloat {
        mode == .pill
            ? NotchIslandGeometry.pillContentInset(barHeight: barHeight, expanded: false)
            : NotchIslandGeometry.Radii.closed.top
    }
}
