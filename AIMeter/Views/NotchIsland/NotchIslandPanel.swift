#if os(macOS)
import AppKit
import SwiftUI

/// The window the island lives in: borderless, transparent, above the
/// menu bar, on every Space and over full-screen apps, and
/// **non-activating** — it never takes the app to the foreground. It is
/// never key either: a key non-activating panel steals the keyboard from
/// whatever the user was typing into, so there is no Esc; a click outside
/// closes it instead (`NotchIslandController`'s mouse monitors).
final class NotchIslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above the menu bar itself: on macOS 26 the bar draws at the
        // status-item level, and at `.statusBar` its titles painted over
        // the island and took its hover. Still below pop-up menus.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // The shadow is drawn by SwiftUI inside the silhouette; a window
        // shadow would outline the transparent frame instead.
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        // Not `isFloatingPanel`: that setter silently resets `level` to
        // `.floating` (3), under the menu bar — which then took every
        // hover and click meant for the island (seen on macOS 27).
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        titleVisibility = .hidden
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit keeps every window's frame below the menu bar; the island
    /// lives *in* it, flush with the screen's top edge, so the frame is
    /// taken as given.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The panel's content view: a plain container around the hosting view
/// (see `NotchIslandController.start` for why the hosting view can't be
/// the content view itself). Hit testing is the hosting view's: outside
/// the silhouette it answers nil, and so does this, so a click in the
/// shadow falls through to the window underneath.
final class NotchIslandContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return subviews.first?.hitTest(local)
    }
}

/// Hosts the SwiftUI island. The panel's frame is fixed and mostly
/// transparent, so hit testing is confined to the slab the view reports
/// (`slab`, in the hosting view's coordinates, updated every frame of
/// the animation): a click beside the wings or in the shadow falls
/// through to whatever is underneath, and a menu title beside the notch
/// stays clickable. Hovering is SwiftUI's own (`onHover` on the slab),
/// which follows the slab's animated frame for free.
final class NotchIslandHostingView<Content: View>: NSHostingView<Content> {
    /// The slab's frame in the root's coordinate space (this view's
    /// bounds, top-left origin). Zero until the view's first layout.
    var slab: CGRect = .zero

    /// Whether `point`, in this view's coordinates, is on the slab. With
    /// no report yet nothing is confined: a wrong guess would make the
    /// island deaf, and the window server's own shape already keeps
    /// clicks off the transparent part.
    func slabContains(_ point: NSPoint) -> Bool {
        guard slab != .zero else { return true }
        let y = isFlipped ? point.y : bounds.height - point.y
        return slab.contains(CGPoint(x: point.x, y: y))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinates.
        guard slabContains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    /// The panel is never key, so every click on it is a "first" click;
    /// AppKit would otherwise spend it on activation and never deliver it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
#endif
