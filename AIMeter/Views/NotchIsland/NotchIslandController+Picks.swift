#if os(macOS)
import AppKit
import SwiftUI

/// What the island's sneak shows, chosen by the user: a click on a
/// session's pet or row puts that session there, a click on an account
/// its figures (the menu bar's too: one `primaryAccountID`), and a swipe
/// or a drag across the island turns to the next or the previous one
/// (`NotchIslandModel.rotation(by:)`: the sessions while one works, else
/// the accounts). Two-finger swipes arrive as scroll events, which a
/// local monitor takes over the island while it is not open (open, the
/// accounts list may need them to scroll).
extension NotchIslandController {
    /// How far the row slides the way a swipe went before springing back.
    static let nudgeDistance: CGFloat = 8
    /// The click that ends a drag which turned the island is not one to
    /// open it with.
    static let tapsIgnoredAfterTurn: TimeInterval = 0.4

    /// A click on the island: it opens, unless the click ended a drag that
    /// just turned it. The same for a click on a pet or an account.
    func tapped() {
        guard !ignoresTaps else { return }
        handle(.tapped)
    }

    func clicked(session id: String) {
        guard !ignoresTaps else { return }
        pickSession(id)
    }

    func clicked(account id: String) {
        guard !ignoresTaps else { return }
        pickAccount(id)
    }

    private var ignoresTaps: Bool {
        tapsIgnoredUntil.map { Date() < $0 } ?? false
    }

    func pickSession(_ id: String) {
        state.sessionPick = NotchIslandModel.SessionPick(id: id, at: Date())
    }

    func pickAccount(_ id: String) {
        guard let model, let prefs else { return }
        if model.isDemoMode {
            if state.demoPrimaryID != id { state.demoPrimaryID = id }
        } else {
            prefs.primaryAccountID = id
        }
    }

    /// The account the island reads instead of the stored one: the demo's
    /// own pick while the demo runs.
    var primaryIDOverride: String? {
        model?.isDemoMode == true ? state.demoPrimaryID : nil
    }

    /// The next (1) or the previous (-1) session or account in the sneak,
    /// while the sneak, a drawn row or a session's pets are in sight: a
    /// bare collapsed notch has nothing to turn.
    func rotate(by step: Int) {
        guard let model, let prefs, interaction.level != .expanded else { return }
        let island = NotchIslandModel.current(model: model, prefs: prefs, sessionPick: state.sessionPick, primaryID: primaryIDOverride)
        guard interaction.level == .peek || interaction.skipsPeek || island.sessions.mark != nil else { return }
        switch island.rotation(by: step) {
        case .session(let id): pickSession(id)
        case .account(let id): pickAccount(id)
        case nil: return
        }
        tapsIgnoredUntil = Date().addingTimeInterval(Self.tapsIgnoredAfterTurn)
        nudge(step)
    }

    /// The row beside the notch slides a few points the way the swipe went
    /// and springs back, so the turn reads as one. Nothing under Reduce
    /// Motion.
    private func nudge(_ step: Int) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        withAnimation(.easeOut(duration: 0.08)) {
            state.nudge = step > 0 ? -Self.nudgeDistance : Self.nudgeDistance
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { self.state.nudge = 0 }
        }
    }

    // MARK: - Two-finger swipes

    func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.swiped(event) else { return event }
            return nil
        }
    }

    func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    /// Whether `event` was a swipe over the island, used here rather than
    /// passed on.
    private func swiped(_ event: NSEvent) -> Bool {
        guard event.window === panel, interaction.level != .expanded, let hosting,
              hosting.slabContains(hosting.convert(event.locationInWindow, from: nil)) else { return false }
        let phase: NotchIslandSwipe.Phase
        if !event.momentumPhase.isEmpty {
            phase = .momentum
        } else if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            phase = .began
        } else if event.phase.contains(.changed) {
            phase = .changed
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            phase = .ended
        } else {
            phase = .wheel
        }
        if let step = swipe.handle(phase, dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, now: Date()) {
            rotate(by: step)
        }
        return true
    }
}
#endif
