import CoreGraphics
import Foundation

/// How the island is drawn on a screen without a notch (an external
/// display, an iMac, a MacBook Air, a MacBook closed on a monitor). A
/// screen with a notch always uses the notch itself — there is nothing
/// else the hardware lets it be. Stored as `Preferences.notchIslandForm`.
/// (Not "style": `NotchIslandStyle` is the island's colors and type.)
enum NotchIslandForm: String, CaseIterable, Sendable {
    /// Fused to the top edge over the menu bar's centre, the silhouette
    /// of a MacBook's notch.
    case notch
    /// A capsule floating in the menu bar, a few points below the top
    /// edge, that opens into a rounded card — the iPhone's island.
    case pill

    var label: String {
        switch self {
        case .notch: String(localized: "Notch")
        case .pill: String(localized: "Pill")
        }
    }

    var caption: String {
        switch self {
        case .notch: String(localized: "Fused to the top edge, like a MacBook’s notch.")
        case .pill: String(localized: "Floats in the menu bar, like the iPhone’s island.")
        }
    }
}

/// Whether the island on a screen without a notch follows the menu bar's
/// height or the user's own (`Preferences.notchIslandCustomHeight`).
enum NotchIslandHeightMode: String, CaseIterable, Sendable {
    case menuBar
    case custom

    var label: String {
        switch self {
        case .menuBar: String(localized: "Menu bar")
        case .custom: String(localized: "Custom")
        }
    }
}

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
    /// thickness instead, which the drawn shapes are sized from.
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
        /// No notch, `NotchIslandForm.notch`: the island draws one,
        /// fused to the top edge over the menu bar's centre —
        /// boring.notch's answer. As wide as its row, the bar tall, and
        /// it grows exactly like the real one.
        case drawn
        /// No notch, `NotchIslandForm.pill`: a capsule floating in the
        /// menu bar (`topInset` below the top edge) that opens into a
        /// rounded card — never clipped to a capsule once it has a body,
        /// which is what made 2.0.0's floating pill unreadable.
        case pill

        /// The island draws its own shape (no hardware notch to hide in),
        /// so its row is always visible unless it is concealed.
        var drawsOwnShape: Bool {
            if case .notch = self { return false }
            return true
        }
    }

    /// What the user chose for a screen without a notch; ignored on a
    /// screen with one.
    struct Options: Equatable {
        var form: NotchIslandForm = .notch
        /// The row's height; nil follows the menu bar.
        var height: CGFloat?
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
    /// The bar's height when a screen reports none (mid-reconfiguration):
    /// the standard menu bar.
    static let fallbackBarHeight: CGFloat = 24
    /// What the "Custom" height may be, in points. Below 20 the mark and
    /// the figures no longer fit; past 44 the row is a banner.
    static let heightRange: ClosedRange<CGFloat> = 20...44
    /// The pill's gap to the top edge (and to the bar's bottom, when it
    /// follows the menu bar): what makes it float rather than hang.
    static let pillInset: CGFloat = 3
    /// The smallest gap the pill keeps to the top edge when a custom
    /// height outgrows the menu bar.
    static let pillMinimumInset: CGFloat = 2
    /// The open pill's corner radius: a rounded card, never a capsule.
    static let pillOpenRadius: CGFloat = 24
    /// The open pill's content inset, side to side.
    static let pillOpenInset: CGFloat = 10
    /// How far past the island the pointer still counts as on it, on a
    /// screen without a notch (`hoverRegion`), and the narrowest that
    /// region gets before the row has reported its width.
    static let hoverSlack: CGFloat = 8
    static let minimumHoverWidth: CGFloat = 120

    static func mode(for screen: Screen, form: NotchIslandForm = .notch) -> Mode {
        guard screen.safeTop > 0, let left = screen.auxLeft, let right = screen.auxRight,
              right.minX > left.maxX else { return form == .pill ? .pill : .drawn }
        return .notch(CGRect(
            x: left.maxX, y: screen.frame.maxY - screen.safeTop,
            width: right.minX - left.maxX, height: screen.safeTop
        ))
    }

    /// The menu bar's height on a screen without a notch; anything too
    /// short to be one (none reported, mid-reconfiguration) is the
    /// standard bar instead.
    static func menuBarHeight(_ screen: Screen) -> CGFloat {
        screen.safeTop >= heightRange.lowerBound ? screen.safeTop : fallbackBarHeight
    }

    static func clampedHeight(_ height: CGFloat) -> CGFloat {
        guard height.isFinite else { return heightRange.lowerBound }
        return min(max(height, heightRange.lowerBound), heightRange.upperBound)
    }

    /// The collapsed slab: with a notch, the notch itself plus the
    /// overhang, the bar tall — black on black, invisible. A drawn shape
    /// has no collapsed width of its own: it is as wide as its row.
    static func closedSize(_ screen: Screen, mode: Mode, options: Options = Options()) -> CGSize {
        switch mode {
        case .notch(let notch):
            return CGSize(width: notch.width + 2 * closedOverhang, height: screen.safeTop)
        case .drawn, .pill:
            return CGSize(width: 0, height: barHeight(screen, mode: mode, options: options))
        }
    }

    /// The row's height. A real notch is what the hardware says. The
    /// drawn notch follows the menu bar; the pill follows it too, inset
    /// by `pillInset` above and below so it floats inside the bar; a
    /// custom height (clamped to `heightRange`) overrides both.
    static func barHeight(_ screen: Screen, mode: Mode, options: Options = Options()) -> CGFloat {
        switch mode {
        case .notch:
            return screen.safeTop
        case .drawn:
            if let height = options.height { return clampedHeight(height) }
            return menuBarHeight(screen)
        case .pill:
            if let height = options.height { return clampedHeight(height) }
            return max(heightRange.lowerBound - 2, menuBarHeight(screen) - 2 * pillInset)
        }
    }

    /// The gap between the screen's top edge and the slab: none for a
    /// notch, real or drawn; for the pill, centred in the menu bar while
    /// it fits, never closer to the edge than `pillMinimumInset` once a
    /// custom height outgrows the bar (it then hangs below it, like the
    /// iPhone's island hangs in the status bar).
    static func topInset(_ screen: Screen, mode: Mode, options: Options = Options()) -> CGFloat {
        guard mode == .pill else { return 0 }
        let bar = barHeight(screen, mode: mode, options: options)
        let centred = ((menuBarHeight(screen) - bar) / 2).rounded(.down)
        return max(pillMinimumInset, centred)
    }

    /// How much bigger than the standard row the content is drawn: 1 at
    /// the default height and for a real notch, growing with a custom
    /// height so a taller island carries larger figures instead of a
    /// sliver of text in a banner.
    static func rowScale(_ screen: Screen, mode: Mode, options: Options = Options()) -> CGFloat {
        let standard: CGFloat
        switch mode {
        case .notch: return 1
        case .drawn: standard = menuBarHeight(screen)
        case .pill: standard = barHeight(screen, mode: mode, options: Options(form: .pill, height: nil))
        }
        let grown = barHeight(screen, mode: mode, options: options) - standard
        return min(1.35, 1 + max(0, grown) / 48)
    }

    /// The pill's corner radius: a capsule while it is one row, a rounded
    /// card once it has a body.
    static func pillRadius(barHeight: CGFloat, expanded: Bool) -> CGFloat {
        expanded ? pillOpenRadius : barHeight / 2
    }

    /// The pill's content inset, side to side: closed, enough that the
    /// row never runs into the rounded ends; open, the card's margin.
    static func pillContentInset(barHeight: CGFloat, expanded: Bool) -> CGFloat {
        expanded ? pillOpenInset : max(0, barHeight / 2 - 8)
    }

    /// The window: fixed, centered on the anchor, wide enough for the
    /// notch with the widest wings on both sides (never narrower than the
    /// expanded island) and tall enough for the gap, the bar and the
    /// tallest body, plus the shadow padding on the sides and below;
    /// flush with the screen's top edge in every mode. Never wider than
    /// the screen.
    static func windowFrame(_ screen: Screen, mode: Mode, options: Options = Options()) -> CGRect {
        let anchor = anchorX(screen, mode: mode)
        let bar = barHeight(screen, mode: mode, options: options)
        let top = topInset(screen, mode: mode, options: options)
        let content: CGSize
        switch mode {
        case .notch(let notch):
            content = CGSize(
                width: max(expandedWidth, notch.width + 2 * (closedOverhang + maxWing)),
                height: bar + maxBodyHeight
            )
        case .drawn, .pill:
            content = CGSize(width: max(expandedWidth, 2 * maxWing), height: top + bar + maxBodyHeight)
        }
        let width = min(screen.frame.width, content.width + 2 * shadowPadding)
        let height = content.height + shadowPadding
        return CGRect(x: anchor - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }

    /// The horizontal center every slab is laid out around: the notch's,
    /// or the screen's for a drawn shape.
    static func anchorX(_ screen: Screen, mode: Mode) -> CGFloat {
        if case .notch(let notch) = mode { return notch.midX }
        return screen.frame.midX
    }

    /// Where the pointer counts as on the island while it is collapsed or
    /// hidden, on a screen without a notch, in screen coordinates: the
    /// collapsed row's place plus `hoverSlack`, from the very top edge
    /// down — the pill's gap included, so the strip above it is not a
    /// dead band. `rowWidth` is the row's reported width (0 before the
    /// first layout). The open island adds its own frame to this.
    static func hoverRegion(_ screen: Screen, mode: Mode, options: Options = Options(), rowWidth: CGFloat) -> CGRect {
        let width = max(rowWidth, minimumHoverWidth) + 2 * hoverSlack
        let height = topInset(screen, mode: mode, options: options) + barHeight(screen, mode: mode, options: options) + hoverSlack / 2
        return CGRect(x: anchorX(screen, mode: mode) - width / 2, y: screen.frame.maxY - height, width: width, height: height)
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
}
