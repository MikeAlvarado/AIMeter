#if os(macOS)
import AppKit
import SwiftUI
import UsageKit

/// What the island's SwiftUI tree reads: how open it is, the screen mode,
/// the bar's height and the collapsed slab's width. Data only; what the
/// tree *does* goes through `NotchIslandActions`. One instance, owned by
/// the controller, handed to the root view. Every write is guarded by an
/// equality check: `@Observable` notifies on every assignment.
@Observable
final class NotchIslandState {
    var level: NotchIslandInteraction.Level = .collapsed
    var mode: NotchIslandGeometry.Mode = .drawn
    /// The top row's height: the menu bar, real notch or drawn.
    var barHeight: CGFloat = NotchIslandGeometry.fallbackBarHeight
    /// The collapsed slab's width: the notch plus its overhang.
    var closedWidth: CGFloat = 0
    /// The first-run reveal is showing: the peek carries its caption.
    var isRevealing = false
    /// The cursor rests on the island: the collapsed slab swells by
    /// `NotchIslandGeometry.hoverFlap` and the slab casts its shadow.
    var isHovering = false
}

/// What the island's tree reports back to the controller.
struct NotchIslandActions {
    var tap: () -> Void
    /// The cursor entered or left the slab (SwiftUI's own hover, which
    /// follows the slab's animated frame).
    var hover: (Bool) -> Void
    /// The slab's current frame in the hosting view's coordinates, so hit
    /// testing stays confined to it.
    var slabChanged: (CGRect) -> Void
}

/// Lifecycle of the island: which screen it sits on, the fixed panel
/// frame, the cursor and click events fed into `NotchIslandInteraction`,
/// the observers that revalidate all of it, and the first-run reveal.
/// One instance, `AppChrome.notchIsland`; `start`/`stop` follow
/// `Preferences.notchIslandEnabled`. The panel is sized once per screen
/// (`NotchIslandGeometry.windowFrame`) and never resized; the island's
/// motion is entirely the view's.
@MainActor
final class NotchIslandController {
    /// The first-run reveal: how long after start it peeks by itself, and
    /// for how long.
    static let revealDelay: Duration = .seconds(2)
    static let revealDuration: Duration = .seconds(6)
    /// How long after a level change the window server is made to
    /// resample which pixels of the transparent window take the mouse —
    /// past the spring, so a closed island stops catching clicks where
    /// the wings were (`resampleMouseShape`).
    static let settleDelay: Duration = .milliseconds(700)

    // Members below are internal rather than private so
    // `NotchIslandController+Screen.swift` can reach them; nothing outside
    // this type's two files should touch them.
    private(set) var isRunning = false
    let state = NotchIslandState()
    private var interaction = NotchIslandInteraction()
    var panel: NotchIslandPanel?
    private var hosting: NotchIslandHostingView<AnyView>?
    private weak var model: UsageModel?
    private weak var prefs: PreferencesModel?
    var screen: NotchIslandGeometry.Screen?
    var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var clickMonitors: [Any] = []
    private var timerTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?

    /// Builds the panel and shows it. Idempotent.
    func start(model: UsageModel, prefs: PreferencesModel) {
        guard !isRunning else { return }
        self.model = model
        self.prefs = prefs
        isRunning = true

        let actions = NotchIslandActions(
            tap: { [weak self] in self?.handle(.tapped) },
            hover: { [weak self] inside in self?.handle(inside ? .entered : .left) },
            slabChanged: { [weak self] frame in self?.slabChanged(frame) }
        )
        let root = NotchIslandRoot(state: state, actions: actions)
            .environment(model)
            .environment(prefs)
            .tint(Theme.accent)
            .environment(\.colorScheme, .dark)
        let hosting = NotchIslandHostingView(rootView: AnyView(root))
        // The window is sized by the controller, never from the content:
        // with intrinsic-content sizing on (the default) AppKit feeds the
        // content's size back into the panel's frame during its own
        // constraints pass, SwiftUI requests another update from inside
        // it, and AppKit raises.
        hosting.sizingOptions = []
        let panel = NotchIslandPanel()
        // The hosting view is never the window's content view either, for
        // the same crash ("more Update Constraints in Window passes than
        // there are views in the window"); a plain container that
        // forwards hit testing keeps the window's size the controller's.
        let container = NotchIslandContainerView(frame: .zero)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        self.hosting = hosting
        self.panel = panel

        observe()
        relocate()
        scheduleRevealIfNeeded()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        [timerTask, settleTask, revealTask].forEach { $0?.cancel() }
        timerTask = nil
        settleTask = nil
        revealTask = nil
        removeClickMonitors()
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        hosting = nil
        interaction = NotchIslandInteraction()
        state.level = .collapsed
        state.isRevealing = false
        state.isHovering = false
    }

    // MARK: - Interaction

    /// Every cursor and click event goes through the pure machine; this
    /// arms the timer it asks for and hands the view the level it lands
    /// on (the view animates it).
    private func handle(_ event: NotchIslandInteraction.Event) {
        let before = interaction.level
        switch event {
        case .entered, .tapped:
            if !state.isHovering { state.isHovering = true }
        case .left, .clickedOutside:
            if state.isHovering { state.isHovering = false }
        default:
            break
        }
        interaction.peeksOnHover = prefs?.notchIslandExpandsOnHover ?? true
        interaction.handle(event)
        armTimer()
        guard interaction.level != before else { return }
        if interaction.level > before, !state.isRevealing {
            // The first time the user opens it, the icon it replaces goes.
            prefs?.markNotchIslandDiscovered()
        }
        levelChanged()
    }

    private func armTimer() {
        timerTask?.cancel()
        timerTask = nil
        let delay: Duration
        let elapsed: NotchIslandInteraction.Event
        switch interaction.timer {
        case .none:
            return
        case .dwell:
            delay = NotchIslandInteraction.dwell
            elapsed = .dwellElapsed
        case .expand:
            delay = NotchIslandInteraction.expand
            elapsed = .expandElapsed
        case .leave:
            delay = NotchIslandInteraction.leave
            elapsed = .leaveElapsed
        }
        timerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.handle(elapsed)
        }
    }

    private func levelChanged() {
        if interaction.level == .collapsed {
            state.isRevealing = false
            // Closed under the cursor (a click, a click outside): no flap
            // until the cursor comes back.
            if state.isHovering { state.isHovering = false }
        }
        if state.level != interaction.level { state.level = interaction.level }
        if interaction.level > .collapsed {
            installClickMonitors()
        } else {
            removeClickMonitors()
        }
        scheduleSettle()
    }

    /// The slab's frame, from the view, on every frame of its animation:
    /// hit testing follows it at once; the window server's mouse shape
    /// is resampled right away for the very first layout (the panel was
    /// shown before the view had drawn anything, so the server may have
    /// sampled it empty — deaf) and once the slab settles after that.
    private func slabChanged(_ frame: CGRect) {
        guard let hosting else { return }
        let first = hosting.slab == .zero && frame != .zero
        let resized = hosting.slab.size != frame.size
        hosting.slab = frame
        if first {
            resampleMouseShape()
        } else if resized {
            scheduleSettle()
        }
    }

    /// Once the spring has settled, resample the mouse shape.
    func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.resampleMouseShape()
        }
    }

    /// Makes the window server recompute which pixels of the transparent
    /// panel take the mouse. It samples the content's alpha when a window
    /// is shown or **resized**, and not reliably otherwise — the shape
    /// went stale (or, sampled before the first draw, stayed empty) when
    /// nothing but the content changed, and `invalidateShadow` alone did
    /// not refresh it for a window without a shadow. So the panel grows
    /// one point downward and shrinks back on the next turn: the content
    /// is top-aligned and the extra point transparent, so nothing visible
    /// moves, and each change makes the server sample what is drawn now.
    func resampleMouseShape() {
        guard let panel, panel.isVisible else { return }
        let frame = panel.frame
        panel.setFrame(CGRect(x: frame.minX, y: frame.minY - 1, width: frame.width, height: frame.height + 1), display: true)
        panel.invalidateShadow()
        Task { @MainActor [weak self] in
            guard let self, let panel = self.panel, panel.frame.height == frame.height + 1 else { return }
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
    }

    /// A click anywhere outside the slab closes an open island. A global
    /// monitor covers other apps (mouse monitors need no permission,
    /// unlike keyboard ones), a local one our own windows. Installed only
    /// while open, so a collapsed island costs nothing.
    private func installClickMonitors() {
        guard clickMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            Task { @MainActor [weak self] in self?.clicked(at: NSEvent.mouseLocation) }
        }) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            if event.window !== self?.panel {
                Task { @MainActor [weak self] in self?.clicked(at: NSEvent.mouseLocation) }
            }
            return event
        }) {
            clickMonitors.append(local)
        }
    }

    private func removeClickMonitors() {
        clickMonitors.forEach { NSEvent.removeMonitor($0) }
        clickMonitors.removeAll()
    }

    private func clicked(at location: NSPoint) {
        guard interaction.level > .collapsed, let panel, let hosting else { return }
        let local = hosting.convert(panel.convertPoint(fromScreen: location), from: nil)
        guard !hosting.slabContains(local) else { return }
        handle(.clickedOutside)
    }

    // MARK: - Reveal

    /// Once, on the first launch with the island on: it peeks by itself
    /// with a caption saying what it is, then closes — so an upgrade
    /// never leaves the user with an island they do not know exists.
    private func scheduleRevealIfNeeded() {
        guard let prefs, !prefs.notchIslandRevealed else { return }
        revealTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.revealDelay)
            guard !Task.isCancelled, let self, self.interaction.level == .collapsed else { return }
            // Marked only once it is actually on screen: a launch that
            // never got this far (a crash, a quit) still owes the reveal.
            self.prefs?.notchIslandRevealed = true
            self.state.isRevealing = true
            self.interaction.reveal()
            self.levelChanged()
            try? await Task.sleep(for: Self.revealDuration)
            guard !Task.isCancelled, self.state.isRevealing, self.interaction.level == .peek, !self.interaction.isInside else { return }
            self.interaction.collapse()
            self.levelChanged()
        }
    }
}
#endif
