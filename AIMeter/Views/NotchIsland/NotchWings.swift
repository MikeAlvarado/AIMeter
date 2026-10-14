#if os(macOS)
import SwiftUI

extension HorizontalAlignment {
    /// The notch's center. The wings' layout (`NotchWings`) defines it
    /// explicitly, at the center of the gap between them; every container
    /// up to the root inherits it from that one child, and the root aligns
    /// it with the window's own center — which the controller put on the
    /// notch. That is how the slab stays fused to the notch, whichever
    /// wings are open, without the window measuring anything: the layout
    /// is natural, the anchor is a guide.
    private enum NotchCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[HorizontalAlignment.center]
        }
    }
    static let notchCenter = HorizontalAlignment(NotchCenter.self)
}

/// The wings beside the notch as one layout of three views: a wing, the
/// notch's gap, a wing, each at its ideal size. Symmetric, both wings take
/// the wider one's width with each one's content at its outer end (the
/// Dynamic Island's compact way), so the slab stays centered on the notch
/// whatever each side holds and grows and shrinks evenly; otherwise each
/// keeps its own width (a one-sided peek). Either way the gap's center is
/// `notchCenter`, which the root aligns with the notch.
struct NotchWings: Layout {
    var symmetric = true

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sides = sideWidths(subviews)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: sides.left + gapWidth(subviews) + sides.right, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let left = sideWidths(subviews).left
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: bounds.minX + left, y: bounds.midY), anchor: .leading, proposal: .unspecified)
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
    }

    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .notchCenter, subviews.count == 3 else { return nil }
        return bounds.minX + sideWidths(subviews).left + gapWidth(subviews) / 2
    }

    private func sideWidths(_ subviews: Subviews) -> (left: CGFloat, right: CGFloat) {
        guard subviews.count == 3 else { return (0, 0) }
        let left = subviews[0].sizeThatFits(.unspecified).width
        let right = subviews[2].sizeThatFits(.unspecified).width
        let side = max(left, right)
        return symmetric ? (side, side) : (left, right)
    }

    private func gapWidth(_ subviews: Subviews) -> CGFloat {
        subviews.count == 3 ? subviews[1].sizeThatFits(.unspecified).width : 0
    }
}
#endif
