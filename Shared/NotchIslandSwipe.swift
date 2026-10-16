import CoreGraphics
import Foundation

/// A sideways swipe across the island as one step: +1 for the next
/// session or account, -1 for the previous. Two fingers on a trackpad
/// (or a Magic Mouse) arrive as scroll events with phases and count once
/// per gesture, past `threshold`; the inertia after the fingers lift
/// never counts. A mouse wheel turned sideways is a step a notch,
/// `wheelInterval` apart; a drag with the mouse button down, a step past
/// `dragThreshold`. The deltas are the content's movement in the user's
/// own scrolling direction (AppKit's `scrollingDeltaX`, negative moving
/// the content left), so the island turns the way a scroll view would
/// for that user: content moving left brings the next one in. Pure,
/// tested.
struct NotchIslandSwipe: Equatable {
    enum Phase: Equatable {
        /// A trackpad gesture starts (fingers down) or carries on.
        case began, changed
        /// The fingers lifted, or the system cancelled the gesture.
        case ended
        /// The inertia after the fingers lifted.
        case momentum
        /// A mouse wheel: no gesture around the event.
        case wheel
    }

    /// How far the content travels sideways before the swipe counts.
    static let threshold: CGFloat = 24
    /// How far a drag goes sideways before it counts.
    static let dragThreshold: CGFloat = 30
    /// A wheel sends several events a notch; one step per this long.
    static let wheelInterval: TimeInterval = 0.3

    private var travel = CGSize.zero
    private var stepped = false
    private var lastWheelStep: Date?

    /// The step this scroll event makes, if any.
    mutating func handle(_ phase: Phase, dx: CGFloat, dy: CGFloat, now: Date) -> Int? {
        switch phase {
        case .began:
            travel = .zero
            stepped = false
            return add(dx, dy)
        case .changed:
            return add(dx, dy)
        case .ended:
            travel = .zero
            stepped = false
            return nil
        case .momentum:
            return nil
        case .wheel:
            guard abs(dx) > abs(dy) else { return nil }
            if let lastWheelStep, now.timeIntervalSince(lastWheelStep) < Self.wheelInterval { return nil }
            lastWheelStep = now
            return dx < 0 ? 1 : -1
        }
    }

    private mutating func add(_ dx: CGFloat, _ dy: CGFloat) -> Int? {
        guard !stepped else { return nil }
        travel.width += dx
        travel.height += dy
        guard abs(travel.width) >= Self.threshold, abs(travel.width) > abs(travel.height) else { return nil }
        stepped = true
        return travel.width < 0 ? 1 : -1
    }

    /// A drag with the mouse button down: a step once it has gone
    /// `dragThreshold` sideways, more sideways than up or down.
    static func step(forDrag translation: CGSize) -> Int? {
        guard abs(translation.width) >= dragThreshold, abs(translation.width) > abs(translation.height) else { return nil }
        return translation.width < 0 ? 1 : -1
    }
}
