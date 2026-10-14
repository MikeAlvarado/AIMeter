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

private struct NotchIslandRowScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// How much larger the collapsed row is drawn than the standard one:
    /// 1 on a real notch and at the default height, more for a taller
    /// custom island (`NotchIslandGeometry.rowScale`). Read by the row's
    /// compact figures and mark only — the expanded account rows keep
    /// their size.
    var notchIslandRowScale: CGFloat {
        get { self[NotchIslandRowScaleKey.self] }
        set { self[NotchIslandRowScaleKey.self] = newValue }
    }
}

/// The wings: with a notch, one on each side of a gap the notch's width,
/// content hugging the notch like the Dynamic Island's; in a drawn notch
/// or the pill, one row. Laid out at its natural width — the slab is as
/// wide as this row — so nothing inside it moves while the island animates.
struct CollapsedRow: View {
    let island: NotchIslandModel
    let mode: NotchIslandGeometry.Mode
    /// The notch's width, the gap between the wings.
    var notchWidth: CGFloat = 0
    @Environment(\.notchIslandRowScale) private var scale

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
            case .drawn, .pill:
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
                        ProviderMark(size: 14 * scale, cornerRadius: 4 * scale, icon: primary.icon)
                    } else {
                        connectGlyph
                    }
                }
                SegmentLine(segments: segments, compact: true, scale: scale)
            }
            .padding(.leading, leading ? Self.outerPadding : Self.innerPadding)
            .padding(.trailing, leading ? Self.innerPadding : Self.outerPadding)
            .fixedSize()
        }
    }

    /// A drawn shape's one row (no notch to hug): the mark and every
    /// chosen figure, the outer inset on both sides, all of it scaled
    /// with a taller custom island.
    private var drawnRow: some View {
        HStack(spacing: 6 * scale) {
            if let primary {
                ProviderMark(size: 14 * scale, cornerRadius: 4 * scale, icon: primary.icon)
            } else {
                connectGlyph
            }
            SegmentLine(segments: island.collapsed.left + island.collapsed.right, compact: true, scale: scale)
        }
        .padding(.horizontal, Self.outerPadding * scale)
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
                    .font(.system(size: 9 * scale, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("Connect")
                    .font(NotchIslandStyle.font(11 * scale))
                    .foregroundStyle(NotchIslandStyle.label)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The Vibe-style run: `5h 42% ↻2h 58m | 7d 61% ↻3d 7h`. Compact drops
/// the reset; the full line keeps it and hangs a 2 pt bar under each
/// segment, as wide as the segment. The expanded island lays its full
/// segments out in `AccountGrid` instead, so accounts share columns.
struct SegmentLine: View {
    let segments: [NotchIslandModel.Segment]
    var compact: Bool
    /// The compact line's size factor (`notchIslandRowScale`); the full
    /// line ignores it.
    var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 8 * scale : 12) {
            ForEach(Array(segments.enumerated()), id: \.element.kind) { index, segment in
                if index > 0 {
                    Text(verbatim: "|")
                        .font(NotchIslandStyle.font(compact ? 11 * scale : 12))
                        .foregroundStyle(NotchIslandStyle.separator)
                }
                SegmentView(segment: segment, compact: compact, scale: scale)
            }
        }
    }
}

struct SegmentView: View {
    let segment: NotchIslandModel.Segment
    var compact: Bool
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SegmentText(segment: segment, compact: compact, scale: scale)
            if !compact {
                SegmentBar(segment: segment)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segment.accessibilityLabel)
    }
}

/// A segment's figures on one line: label, percent in its level's color,
/// and (full line only) the reset.
struct SegmentText: View {
    let segment: NotchIslandModel.Segment
    var compact: Bool
    var scale: CGFloat = 1

    var body: some View {
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
        .font(NotchIslandStyle.font((compact ? 11 : 12) * scale))
        // A segment is one line, always.
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// The 2 pt bar under a full segment, as wide as whatever holds it.
struct SegmentBar: View {
    let segment: NotchIslandModel.Segment

    var body: some View {
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
#endif
