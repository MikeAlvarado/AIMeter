#if os(macOS)
import SwiftUI

/// The island's silhouette: a black slab flush with the screen's top edge,
/// its bottom corners rounded by `bottom` and its top corners flared
/// outward by two concave "ears" of `top`, so the slab reads as the notch
/// having grown rather than a bar painted over the menu bar. The ears
/// live inside the rect: the straight sides run `top` in from each edge
/// and the top edge spans the full width.
///
/// Both radii are `animatableData`, so they ease from the notch's own
/// pair to the rounder open pair (`NotchIslandGeometry.Radii`) on the
/// same spring as the slab's size.
struct NotchShape: Shape {
    var top: CGFloat = NotchIslandGeometry.Radii.closed.top
    var bottom: CGFloat = NotchIslandGeometry.Radii.closed.bottom

    init(radii: NotchIslandGeometry.Radii = .closed) {
        top = radii.top
        bottom = radii.bottom
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let ear = max(0, min(top, rect.width / 4, rect.height / 2))
        let radius = max(0, min(bottom, (rect.width - 2 * ear) / 2, rect.height - ear))
        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY))
        // Left ear: the fillet from the top edge down onto the left side.
        path.addQuadCurve(to: CGPoint(x: minX + ear, y: minY + ear), control: CGPoint(x: minX + ear, y: minY))
        path.addLine(to: CGPoint(x: minX + ear, y: maxY - radius))
        path.addQuadCurve(to: CGPoint(x: minX + ear + radius, y: maxY), control: CGPoint(x: minX + ear, y: maxY))
        path.addLine(to: CGPoint(x: maxX - ear - radius, y: maxY))
        path.addQuadCurve(to: CGPoint(x: maxX - ear, y: maxY - radius), control: CGPoint(x: maxX - ear, y: maxY))
        path.addLine(to: CGPoint(x: maxX - ear, y: minY + ear))
        // Right ear, mirrored.
        path.addQuadCurve(to: CGPoint(x: maxX, y: minY), control: CGPoint(x: maxX - ear, y: minY))
        path.closeSubpath()
        return path
    }
}

/// The black surface, applied to the island's content: the content is
/// inset by the ears so nothing sits in the fillets, backed with pure
/// black (the color of the hardware, whatever the appearance), clipped
/// to the silhouette, with a one-point black line along the top so the
/// anti-aliased edge never shows a seam against the bezel, and a shadow
/// only while the island is open or hovered — collapsed it is the notch
/// and casts none. The drawn notch (a screen without one) is the same
/// silhouette, so it fuses to the top edge the way the real one does.
/// The whole stack is boring.notch's, rebuilt.
struct NotchIslandSurface: ViewModifier {
    let mode: NotchIslandGeometry.Mode
    var radii: NotchIslandGeometry.Radii = .closed
    var casts = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, radii.top)
            .background(Color.black)
            .clipShape(NotchShape(radii: radii))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1)
                    .padding(.horizontal, radii.top)
            }
            .shadow(color: casts ? .black.opacity(0.7) : .clear, radius: 6)
    }
}

extension View {
    func notchIslandSurface(mode: NotchIslandGeometry.Mode, radii: NotchIslandGeometry.Radii = .closed, casts: Bool = false) -> some View {
        modifier(NotchIslandSurface(mode: mode, radii: radii, casts: casts))
    }
}
#endif
