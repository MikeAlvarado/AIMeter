#if os(macOS)
import SwiftUI
import UsageKit

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

/// The wings: with a notch, one on each side of a gap the notch's width
/// (`NotchWings`), as wide as each other whenever both have something to
/// show, so the slab stays centered on the notch; in a drawn notch or the
/// pill, one row. Laid out at its natural width — the slab is as wide as
/// this row — so nothing inside it moves while the island animates.
/// Heading the expanded island (`fill`), the row spans the body's width
/// instead: each wing reaches out to the body's edge, so the figures line
/// up with the accounts, the sessions and the footer under them. A
/// Claude Code session never shows here on a real notch: the collapsed
/// island shows the sessions (`SessionWings`), the peek the figures, one
/// or the other.
struct CollapsedRow: View {
    let island: NotchIslandModel
    let mode: NotchIslandGeometry.Mode
    /// The notch's width, the gap between the wings.
    var notchWidth: CGFloat = 0
    /// The row's height, which a Claude Code session's pets are sized to.
    var barHeight: CGFloat = 24
    /// The expanded body's width, when the row heads it; nil for the peek.
    var fill: CGFloat?
    /// How far a drawn row may reach either side of the screen's centre
    /// without covering the menu bar's own items
    /// (`NotchIslandState.availableWing`), which only the session's name
    /// gives way to; nil when nothing limits it.
    var availableWing: CGFloat?
    @Environment(\.notchIslandRowScale) private var scale
    @Environment(\.displayScale) private var displayScale
    @Environment(\.notchIslandActions) private var actions

    /// Inset between a wing's content and the notch.
    static let innerPadding: CGFloat = 12
    /// Inset between a wing's content and the slab's ear.
    static let outerPadding: CGFloat = 10

    var body: some View {
        HStack(spacing: 0) {
            switch mode {
            case .notch:
                // Heading the expanded island each wing reaches out to the
                // body's edge; peeking, both come out as wide whenever both
                // hold something (a one-sided layout keeps its one wing).
                let reach = fill.map { max(0, ($0 - notchWidth) / 2) } ?? 0
                let bothSides = (!island.collapsed.left.isEmpty || primary == nil) && !island.collapsed.right.isEmpty
                NotchWings(symmetric: fill != nil || bothSides) {
                    wing(island.collapsed.left, leading: true)
                        .frame(minWidth: reach, alignment: .leading)
                    Color.clear.frame(width: notchWidth, height: 0)
                    wing(island.collapsed.right, leading: false)
                        .frame(minWidth: reach, alignment: .trailing)
                }
            case .drawn, .pill:
                drawnRow
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel([island.accessibilityLabel, island.sessions.markLabel].compactMap { $0 }.joined(separator: "; "))
    }

    private var primary: NotchIslandModel.Account? { island.primaryAccount }

    /// One wing: the figures, after the account's mark on the left. Always
    /// a view, an empty one for a side with nothing, so `NotchWings` has
    /// its three.
    @ViewBuilder
    private func wing(_ segments: [NotchIslandModel.Segment], leading: Bool) -> some View {
        let showsIdentity = leading && (!segments.isEmpty || primary == nil)
        if !segments.isEmpty || showsIdentity {
            HStack(spacing: 6) {
                if showsIdentity {
                    if let primary {
                        ProviderMark(size: 14 * scale, cornerRadius: 4 * scale, icon: primary.icon)
                    } else {
                        connectGlyph
                    }
                }
                SegmentLine(segments: segments, compact: true, scale: scale)
            }
            .padding(.leading, leading ? edgePadding : Self.innerPadding)
            .padding(.trailing, leading ? Self.innerPadding : edgePadding)
            .fixedSize()
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    /// A drawn shape's one row (no notch to hug, so nothing to swap on a
    /// hover): the mark and every chosen figure, the outer inset on both
    /// sides, all of it scaled with a taller custom island; a Claude Code
    /// session's pets (or mark) and count at its two ends, except heading
    /// the expanded island, where each pet is in its session's row. With
    /// the session's name on, the row reads like the notch's: the lead's
    /// pet and name first, the figures where the notch would be, the other
    /// pets and the count last.
    private var drawnRow: some View {
        let sessions = fill == nil ? island.sessions : .none
        return Group {
            if sessions.showsName, let lead = sessions.lead {
                namedRow(sessions: sessions, lead: lead)
            } else {
                HStack(spacing: 6 * scale) {
                    if sessions.showsPets {
                        if !sessions.pets.isEmpty {
                            PetGroup(slots: sessions.pets, pixel: petPixel, leadID: sessions.lead?.id)
                        }
                    } else if let mark = sessions.mark {
                        SessionMark(mark: mark, scale: scale)
                    }
                    identity
                    SegmentLine(segments: island.collapsed.left + island.collapsed.right, compact: true, scale: scale)
                    if fill != nil {
                        Spacer(minLength: 0)
                    }
                    if sessions.count > 0 {
                        SessionCount(count: sessions.count, scale: scale)
                    }
                }
            }
        }
        .padding(.horizontal, fill == nil ? Self.outerPadding * scale : ExpandedContent.horizontalPadding)
        .frame(width: fill)
        .fixedSize()
    }

    /// The drawn row with the lead session's name, up to
    /// `NotchIslandGeometry.drawnNameWidth` and only in the room the menu
    /// bar leaves (`availableWing`, from the screen's centre).
    private func namedRow(sessions: NotchIslandModel.Sessions, lead: NotchIslandModel.Sessions.Row) -> some View {
        NamedRowLayout(spacing: 6 * scale, limit: availableWing.map { 2 * ($0 - Self.outerPadding * scale) }) {
            if sessions.showsPets {
                PetGroup(slots: sessions.leftPets(named: true), pixel: petPixel, leadID: lead.id)
            } else if let mark = sessions.mark {
                SessionMark(mark: mark, scale: scale)
            }
            SessionName(name: lead.name, maxWidth: NotchIslandGeometry.drawnNameWidth * scale, scale: scale)
                .clipped()
                .layoutValue(key: NamedRowLayout.IsName.self, value: true)
            identity
            SegmentLine(segments: island.collapsed.left + island.collapsed.right, compact: true, scale: scale)
            if sessions.showsPets, !sessions.rightPets(named: true).isEmpty {
                PetGroup(slots: sessions.rightPets(named: true), pixel: petPixel, leadID: lead.id)
            }
            SessionCount(count: sessions.count, scale: scale)
        }
    }

    /// The account's mark, or the "Connect" affordance with none.
    @ViewBuilder
    private var identity: some View {
        if let primary {
            ProviderMark(size: 14 * scale, cornerRadius: 4 * scale, icon: primary.icon)
        } else {
            connectGlyph
        }
    }

    /// Inset between a wing's content and the slab's outer edge: the body's
    /// own padding while the row heads the expanded island.
    private var edgePadding: CGFloat {
        fill == nil ? Self.outerPadding : ExpandedContent.horizontalPadding
    }

    /// The pets' pixel: the same as beside the collapsed notch.
    private var petPixel: CGFloat {
        SessionPet.pixelSize(beside: barHeight, displayScale: displayScale)
    }

    /// With nothing connected the wing is the "Connect" affordance,
    /// routed through the Dashboard like every other surface's.
    private var connectGlyph: some View {
        Button {
            AppChrome.connect(.add)
            actions?.close()
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
