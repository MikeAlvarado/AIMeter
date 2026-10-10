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

/// The pill's silhouette: a rounded rectangle with continuous corners
/// whose radius never exceeds half the shorter side — a capsule while it
/// is one row, a rounded card once it has a body. Never a capsule around
/// a body: 2.0.0's floating pill clipped its expanded content with one
/// (a 300-pt-tall capsule has 150-pt ends), which is what made it
/// unreadable. The radius is `animatableData`, eased on the slab's spring.
struct IslandPillShape: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let resolved = max(0, min(radius, rect.width / 2, rect.height / 2))
        return RoundedRectangle(cornerRadius: resolved, style: .continuous).path(in: rect)
    }
}

/// The black surface, applied to the island's content: the content is
/// inset so nothing sits in the curves, backed with pure black (the color
/// of the hardware, whatever the appearance), clipped to the silhouette,
/// and shadowed only while the island is open or hovered — collapsed it
/// is the notch and casts none. A notch, real or drawn, is the eared
/// `NotchShape` with a one-point black line along the top so its
/// anti-aliased edge never shows a seam against the bezel; the pill is
/// `IslandPillShape`, which has no top edge to hide. The notch stack is
/// boring.notch's, rebuilt.
struct NotchIslandSurface: ViewModifier {
    let mode: NotchIslandGeometry.Mode
    /// The row's height — the pill's closed radius is half of it.
    var barHeight: CGFloat = 0
    var expanded = false
    var casts = false

    @ViewBuilder
    func body(content: Content) -> some View {
        switch mode {
        case .notch, .drawn:
            let radii: NotchIslandGeometry.Radii = expanded ? .open : .closed
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
        case .pill:
            content
                .padding(.horizontal, NotchIslandGeometry.pillContentInset(barHeight: barHeight, expanded: expanded))
                .background(Color.black)
                .clipShape(IslandPillShape(radius: NotchIslandGeometry.pillRadius(barHeight: barHeight, expanded: expanded)))
                .shadow(color: casts ? .black.opacity(0.7) : .clear, radius: 6)
        }
    }
}

extension View {
    func notchIslandSurface(mode: NotchIslandGeometry.Mode, barHeight: CGFloat, expanded: Bool = false, casts: Bool = false) -> some View {
        modifier(NotchIslandSurface(mode: mode, barHeight: barHeight, expanded: expanded, casts: casts))
    }
}
#endif
