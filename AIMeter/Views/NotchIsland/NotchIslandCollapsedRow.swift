#if os(macOS)
import SwiftUI
import UsageKit

extension HorizontalAlignment {
    /// The notch's center. The gap between the wings defines it
    /// explicitly; every container up to the root inherits it from that
    /// one child, and the root aligns it with the window's own center —
    /// which the controller put on the notch. That is how an asymmetric
    /// peek (one wing closed) stays fused to the notch without anyone
    /// measuring a wing: the layout is natural, the anchor is a guide.
    private enum NotchCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[HorizontalAlignment.center]
        }
    }
    static let notchCenter = HorizontalAlignment(NotchCenter.self)
}

/// The wings: with a notch, one on each side of a gap the notch's width,
/// content hugging the notch like the Dynamic Island's; in the drawn
/// notch, one row. Laid out at its natural width — the slab is as wide
/// as this row — so nothing inside it moves while the island animates.
struct CollapsedRow: View {
    let island: NotchIslandModel
    let mode: NotchIslandGeometry.Mode
    /// The notch's width, the gap between the wings.
    var notchWidth: CGFloat = 0

    /// Inset between a wing's content and the notch.
    static let innerPadding: CGFloat = 12
    /// Inset between a wing's content and the slab's ear.
    static let outerPadding: CGFloat = 10

    var body: some View {
        HStack(spacing: 0) {
            switch mode {
            case .notch:
                wing(island.collapsed.left, leading: true)
                Color.clear
                    .frame(width: notchWidth)
                    .alignmentGuide(.notchCenter) { $0.width / 2 }
                wing(island.collapsed.right, leading: false)
            case .drawn:
                drawnRow
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(island.accessibilityLabel)
    }

    private var primary: NotchIslandModel.Account? { island.primaryAccount }

    @ViewBuilder
    private func wing(_ segments: [NotchIslandModel.Segment], leading: Bool) -> some View {
        if !segments.isEmpty || primary == nil && leading {
            HStack(spacing: 6) {
                if leading {
                    if let primary {
                        ProviderMark(size: 14, cornerRadius: 4, icon: primary.icon)
                    } else {
                        connectGlyph
                    }
                }
                SegmentLine(segments: segments, compact: true)
            }
            .padding(.leading, leading ? Self.outerPadding : Self.innerPadding)
            .padding(.trailing, leading ? Self.innerPadding : Self.outerPadding)
            .fixedSize()
        }
    }

    /// The drawn notch's one row: the mark and every chosen figure, the
    /// outer inset on both sides (there is no notch to hug).
    private var drawnRow: some View {
        HStack(spacing: 6) {
            if let primary {
                ProviderMark(size: 14, cornerRadius: 4, icon: primary.icon)
            } else {
                connectGlyph
            }
            SegmentLine(segments: island.collapsed.left + island.collapsed.right, compact: true)
        }
        .padding(.horizontal, Self.outerPadding)
        .fixedSize()
    }

    /// With nothing connected the wing is the "Connect" affordance,
    /// routed through the Dashboard like every other surface's.
    private var connectGlyph: some View {
        Button {
            AppChrome.connect(.add)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: ProviderMark.defaultSymbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("Connect")
                    .font(NotchIslandStyle.font(11))
                    .foregroundStyle(NotchIslandStyle.label)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The Vibe-style run: `5h 42% ↻2h 58m | 7d 61% ↻3d 7h`. Compact drops
/// the reset; the full line keeps it and hangs a 2 pt bar under each
/// segment, as wide as the segment.
struct SegmentLine: View {
    let segments: [NotchIslandModel.Segment]
    var compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 8 : 12) {
            ForEach(Array(segments.enumerated()), id: \.element.kind) { index, segment in
                if index > 0 {
                    Text(verbatim: "|")
                        .font(NotchIslandStyle.font(compact ? 11 : 12))
                        .foregroundStyle(NotchIslandStyle.separator)
                }
                SegmentView(segment: segment, compact: compact)
            }
        }
    }
}

struct SegmentView: View {
    let segment: NotchIslandModel.Segment
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(segment.label)
                    .foregroundStyle(NotchIslandStyle.label)
                Text(segment.percent)
                    .foregroundStyle(NotchIslandStyle.tint(segment.tint))
                if !compact, let reset = segment.reset {
                    // The reset glyph says what the third figure is: a
                    // time until the window turns over, not more usage.
                    Text(verbatim: "↻\(reset)")
                        .foregroundStyle(NotchIslandStyle.reset)
                }
            }
            .font(NotchIslandStyle.font(compact ? 11 : 12))
            // A segment is one line, always.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            if !compact {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NotchIslandStyle.track)
                        Capsule().fill(NotchIslandStyle.tint(segment.tint))
                            .frame(width: proxy.size.width * segment.fraction)
                    }
                }
                .frame(height: 2)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segment.accessibilityLabel)
    }
}
#endif
