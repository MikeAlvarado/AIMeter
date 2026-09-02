import SwiftUI
import UsageKit
#if os(iOS)
import UIKit
#endif

/// Where each Dashboard account section sits, keyed by accountID and
/// resolved in the Dashboard's own named coordinate space.
///
/// The reorder gesture needs this because it isn't a drag *session*: there
/// is no system drop target to ask "is the finger over you". The gesture
/// gets a location, and these rects are what turn that location into "the
/// card it would land on". Sections never overlap, so a plain merge is
/// enough — every section publishes only its own entry.
struct AccountSectionFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The Dashboard content's vertical position inside its `ScrollView` —
/// the one signal that tells a scroll from a hold. See
/// `DashboardView.ScrollMovementTracker` for why the reorder gesture needs
/// it: `LongPressGesture` cannot see a scroll at all.
struct DashboardScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// One step of a hold-then-drag reorder, with locations in the Dashboard's
/// `reorderSpace`. Both gesture implementations below report through this
/// so `DashboardView` has a single handler.
enum ReorderPhase {
    /// The hold completed; the card may lift. Carries the finger's location.
    case began(CGPoint)
    /// The finger moved while lifted.
    case moved(CGPoint)
    case ended
    case cancelled
}

#if os(iOS)
/// Hold-then-drag as a plain UIKit `UILongPressGestureRecognizer`, for iOS
/// 18 and later.
///
/// SwiftUI's own gestures are the wrong tool for this inside a `ScrollView`
/// on iOS 18+: a `LongPressGesture.sequenced(before: DragGesture)` attached
/// to a card — with `.gesture` *or* `.simultaneousGesture` — makes the
/// ScrollView refuse to pan for any touch that begins on that card
/// (verified on the iOS 26 simulator: a flick on a card did nothing; the
/// same flick in the gap between cards scrolled; with the gesture removed,
/// the flick on the card scrolled). Since cards are nearly all of the
/// Dashboard, that made it effectively unscrollable. And even where the pan
/// did win, `LongPressGesture` measures movement in the card's own
/// coordinate space, which scrolls *with* the finger — so a scrolling finger
/// never "moves", the press completed mid-scroll, and the card lifted while
/// the list was still going (the shadow-while-scrolling seen on a device).
///
/// UIKit has had the right semantics for this since UIScrollView existed:
/// the scroll view's pan and this recognizer are mutually exclusive, so a
/// finger that moves before `minimumPressDuration` starts the pan and
/// *cancels* the press, and a press that completes first prevents the pan
/// for the rest of that touch — hold to drag, move to scroll, never both.
/// A continuous recognizer, it keeps reporting `.changed` with the finger's
/// location after recognising, which is the drag; no second gesture needed.
@available(iOS 18.0, *)
struct ReorderPressRecognizer: UIGestureRecognizerRepresentable {
    let coordinateSpace: NamedCoordinateSpace
    let onPhase: (ReorderPhase) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        // The platform's own long-press duration and movement allowance —
        // the same values `LongPressGesture` defaults to.
        recognizer.minimumPressDuration = 0.5
        recognizer.allowableMovement = 10
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            onPhase(.began(context.converter.location(in: coordinateSpace)))
        case .changed:
            onPhase(.moved(context.converter.location(in: coordinateSpace)))
        case .ended:
            onPhase(.ended)
        case .cancelled, .failed:
            onPhase(.cancelled)
        default:
            break
        }
    }
}
#endif

/// Outlines the section a release would drop onto. The only feedback the
/// reorder gives besides the card following the finger, since it resolves
/// on release rather than live — so it has to be unambiguous about which
/// slot the card is about to take.
struct AccountDropHighlight: View {
    let isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(Theme.accent, lineWidth: 2)
            .opacity(isTargeted ? 1 : 0)
            .allowsHitTesting(false)
    }
}
