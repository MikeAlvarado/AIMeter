import CoreGraphics
import Foundation

/// Where the macOS notch island's window sits and the sizes its content
/// is built from, from plain rects — no AppKit, so it is unit-tested.
/// The controller feeds it `NSScreen.frame`, `safeAreaInsets.top` and
/// the two auxiliary top areas and gets the window's frame back in the
/// same **AppKit coordinates** (origin at the screen's bottom-left, y
/// growing upward), which is what `NSWindow.setFrame` takes.
///
/// The window is sized **once**, to the largest island it can ever show
/// plus room for the shadow, and never resized: everything that moves is
/// SwiftUI layout inside it (see `NotchIslandRoot`). That is the recipe
/// boring.notch runs on, and what makes the motion one spring instead of
/// a window resize racing a re-layout.
enum NotchIslandGeometry {
    /// One display, as the controller reads it. On a Mac with a notch
    /// `safeTop` is the notch's height (the menu bar's too, 32 pt on a
    /// 14"/16" MacBook Pro — never `NSStatusBar.thickness`, which stays 22)
    /// and the auxiliary areas are the menu bar's two halves. Without a
    /// notch the areas are nil and `safeTop` carries the menu bar's
    /// thickness instead, so the pill knows how far down to sit.
    struct Screen: Equatable {
        var frame: CGRect
        var safeTop: CGFloat
        var auxLeft: CGRect?
        var auxRight: CGRect?
    }

    enum Mode: Equatable {
        /// The notch's rect, in screen coordinates: between the two
        /// auxiliary areas, the full menu bar height, flush with the top.
        case notch(CGRect)
        /// No notch: a floating capsule under the menu bar, centered.
        case pill
    }

    /// The corner radii of the black slab, animated between the two as
    /// the island opens: the top ones are the concave "ears" that fuse it
    /// to the bezel, the bottom ones its rounded chin. The closed pair is
    /// the notch's own; the open pair is rounder, like the Dynamic
    /// Island's expanded state.
    struct Radii: Equatable {
        var top: CGFloat
        var bottom: CGFloat
        static let closed = Radii(top: 6, bottom: 14)
        static let open = Radii(top: 19, bottom: 24)
    }

    /// How far the collapsed slab reaches past the notch on each side.
    /// Under the notch the slab is invisible; this hair of black beside
    /// it covers the bezel's anti-aliased edge, so the island never shows
    /// a seam when it opens.
    static let closedOverhang: CGFloat = 2
    /// How much the collapsed slab swells while the cursor rests on it
    /// (width and height), before any peek: the hint that it is alive.
    static let hoverFlap = CGSize(width: 10, height: 3)
    /// The expanded island's minimum width; wider when the wings need it.
    static let expandedWidth: CGFloat = 440
    /// The widest a wing is allowed to be, and the tallest the expanded
    /// body: not limits the content is laid out against, but what the
    /// fixed window is sized to hold. Content past them is clipped by the
    /// window, never re-flowed.
    static let maxWing: CGFloat = 240
    static let maxBodyHeight: CGFloat = 460
    /// Room the window keeps around the slab for the drawn shadow.
    static let shadowPadding: CGFloat = 20
    static let pillHeight: CGFloat = 28
    /// Horizontal padding the pill adds around its content.
    static let pillPadding: CGFloat = 12
    /// Gap between the menu bar and the pill.
    static let pillGap: CGFloat = 6

    static func mode(for screen: Screen) -> Mode {
        guard screen.safeTop > 0, let left = screen.auxLeft, let right = screen.auxRight,
              right.minX > left.maxX else { return .pill }
        return .notch(CGRect(
            x: left.maxX, y: screen.frame.maxY - screen.safeTop,
            width: right.minX - left.maxX, height: screen.safeTop
        ))
    }

    /// The collapsed slab: with a notch, the notch itself plus the
    /// overhang, the bar tall — black on black, invisible. The pill has
    /// no collapsed size of its own: it is as wide as its row.
    static func closedSize(_ screen: Screen, mode: Mode) -> CGSize {
        switch mode {
        case .notch(let notch):
            return CGSize(width: notch.width + 2 * closedOverhang, height: screen.safeTop)
        case .pill:
            return CGSize(width: 0, height: pillHeight)
        }
    }

    /// The row's height: the menu bar with a notch, the pill without.
    static func barHeight(_ screen: Screen, mode: Mode) -> CGFloat {
        closedSize(screen, mode: mode).height
    }

    /// The window: fixed, centered on the anchor, wide enough for the
    /// notch with the widest wings on both sides (never narrower than the
    /// expanded island) and tall enough for the bar plus the tallest
    /// body, plus the shadow padding on the sides and below; flush with
    /// the screen's top edge (the pill's, `pillGap` under the bar). Never
    /// wider than the screen.
    static func windowFrame(_ screen: Screen, mode: Mode) -> CGRect {
        let anchor = anchorX(screen, mode: mode)
        let content: CGSize
        switch mode {
        case .notch(let notch):
            content = CGSize(
                width: max(expandedWidth, notch.width + 2 * (closedOverhang + maxWing)),
                height: screen.safeTop + maxBodyHeight
            )
        case .pill:
            content = CGSize(width: max(expandedWidth, 2 * maxWing), height: pillHeight + maxBodyHeight)
        }
        let width = min(screen.frame.width, content.width + 2 * shadowPadding)
        let height = content.height + shadowPadding
        let top: CGFloat
        switch mode {
        case .notch: top = screen.frame.maxY
        case .pill: top = pillTop(screen)
        }
        return CGRect(x: anchor - width / 2, y: top - height, width: width, height: height)
    }

    /// The horizontal center every slab is laid out around: the notch's,
    /// or the screen's for the pill.
    static func anchorX(_ screen: Screen, mode: Mode) -> CGFloat {
        if case .notch(let notch) = mode { return notch.midX }
        return screen.frame.midX
    }

    /// Which screen hosts the island: the first with a notch, else the
    /// main screen (index 0, as `NSScreen.screens` orders them); nil with
    /// no screens at all (headless, or mid-reconfiguration).
    static func target(screens: [Screen]) -> Int? {
        if let index = screens.firstIndex(where: { if case .notch = mode(for: $0) { true } else { false } }) {
            return index
        }
        return screens.isEmpty ? nil : 0
    }

    private static func pillTop(_ screen: Screen) -> CGFloat {
        screen.frame.maxY - screen.safeTop - pillGap
    }
}
