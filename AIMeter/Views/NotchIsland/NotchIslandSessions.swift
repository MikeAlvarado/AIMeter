#if os(macOS)
import SwiftUI
import UsageKit

/// The island beside the notch while a Claude Code session works, waits
/// or just finished, on a real notch, read the way Vibe Island's compact
/// island reads. Collapsed: the lead session's pet (the one waiting for
/// permission, else the newest at work), the second of three beside it,
/// or with `Sessions.showsName` (off by default) its name instead, and
/// the other pets and the count on the notch's right. Peeking: that session in
/// full, its name on the left and what it is doing on the right ("Working
/// for 3m"), instead of the usage figures, which the peek shows only with
/// no session at work: one or the other, never both. With pets off, the
/// mark stands where the pets would. Both sides as wide as each other
/// (`NotchWings`), so the island stays centered on the notch (see "Claude
/// Code sessions" in the repo-root CLAUDE.md).
struct SessionWings: View {
    let sessions: NotchIslandModel.Sessions
    let notchWidth: CGFloat
    var extraWidth: CGFloat = 0
    /// The bar's height, which the pets are sized to.
    var barHeight: CGFloat = 32
    var peeking = false
    /// How wide each side may grow without covering the menu bar's own
    /// items (`NotchIslandState.availableWing`), read while collapsed:
    /// the name takes what is left beside the pet, and none at all below
    /// `SessionName.minimumWidth`, the island then as short as without it.
    var availableWing: CGFloat?
    @Environment(\.displayScale) private var displayScale

    /// Inset between a side's content and the notch, and the slab's ear:
    /// air on both sides of a pet rather than one against the curve.
    static let innerPadding: CGFloat = 10
    static let outerPadding: CGFloat = 12

    var body: some View {
        let nameWidth = peeking ? SessionName.maxWidth : fittedNameWidth
        let named = peeking || (sessions.showsName && nameWidth >= SessionName.minimumWidth) ? sessions.lead : nil
        NotchWings {
            HStack(spacing: 8) {
                if sessions.showsPets {
                    PetGroup(slots: sessions.leftPets(named: named != nil), pixel: pixel)
                } else if let mark = sessions.mark {
                    SessionMark(mark: mark)
                }
                if let named {
                    SessionName(name: named.name, maxWidth: nameWidth)
                        .transition(.notchSwap)
                }
            }
            .padding(.leading, Self.outerPadding)
            .padding(.trailing, Self.innerPadding)
            Color.clear.frame(width: notchWidth + extraWidth, height: 0)
            HStack(spacing: 8) {
                if peeking, let lead = sessions.lead {
                    SessionDetail(row: lead)
                        .transition(.notchSwap)
                } else if sessions.showsPets, !sessions.rightPets(named: named != nil).isEmpty {
                    PetGroup(slots: sessions.rightPets(named: named != nil), pixel: pixel)
                        .transition(.notchSwap)
                }
                SessionCount(count: sessions.count)
            }
            .padding(.leading, Self.innerPadding)
            .padding(.trailing, Self.outerPadding)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(peeking ? sessions.lead?.accessibilityLabel ?? "" : sessions.markLabel ?? "")
    }

    private var pixel: CGFloat {
        SessionPet.pixelSize(beside: barHeight, displayScale: displayScale)
    }

    /// The name's room beside the lead's pet (or mark) within
    /// `availableWing`, past the paddings, the pet and its "!".
    private var fittedNameWidth: CGFloat {
        guard let availableWing else { return SessionName.maxWidth }
        let waits = sessions.pets.first?.pose == .waiting
        let lead = sessions.showsPets ? CGFloat(SessionPet.canvasWidth) * pixel + (waits ? 3 * pixel : 0) : 14
        return min(SessionName.maxWidth, availableWing - Self.outerPadding - lead - 8 - Self.innerPadding)
    }
}

extension AnyTransition {
    /// What sits beside the notch changing over (the sessions for the
    /// peek's figures, a session's pets for what it is doing, and back):
    /// the old fades out before the new fades in, so the two never show
    /// over each other.
    static let notchSwap = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.12)),
        removal: .opacity.animation(.easeIn(duration: 0.12))
    )
}

/// A spinner while a session works, a yellow alert while one waits for
/// permission, a check for a few seconds after one finishes. The spinner
/// is the `rays` symbol lit ray by ray (a symbol effect, which the system
/// animates, so the collapsed island still runs no timer of its own) in
/// the labels' white: the system's progress indicator draws a dim gray on
/// black, next to a count that reads far brighter. Still under Reduce
/// Motion.
struct SessionMark: View {
    let mark: NotchIslandModel.Sessions.Mark
    var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch mark {
            case .working:
                Image(systemName: "rays")
                    .foregroundStyle(NotchIslandStyle.label)
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeating, isActive: !reduceMotion)
            case .waiting:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Theme.islandWarning)
            case .finished:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
        }
        .font(.system(size: 12 * scale, weight: .semibold))
        .frame(width: 14 * scale, height: 14 * scale)
        .accessibilityHidden(true)
    }
}

/// How many sessions the pets stand for, in a small badge like Vibe
/// Island's count.
struct SessionCount: View {
    let count: Int
    var scale: CGFloat = 1

    var body: some View {
        Text(count.formatted())
            .font(NotchIslandStyle.font(10 * scale))
            .foregroundStyle(NotchIslandStyle.label)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5 * scale)
            .padding(.vertical, 1 * scale)
            .background(RoundedRectangle(cornerRadius: 4 * scale, style: .continuous).fill(NotchIslandStyle.track))
            .accessibilityHidden(true)
    }
}


/// The lead session's name beside its pet, in the rows' type, cut short
/// past `maxWidth`. Beside a real notch the panel is sized once for wings
/// up to `NotchIslandGeometry.maxWing` (240 pt): the slab's ear, the
/// paddings, the pet with its "!" and this name stay well inside it, since
/// a wider slab is clipped at the window's edge and loses its rounded
/// corners. A drawn row has no notch to keep clear and a panel sized for
/// it, so there the name reaches `NotchIslandGeometry.drawnNameWidth`.
struct SessionName: View {
    let name: String
    var maxWidth = Self.maxWidth
    /// The drawn row's size factor (`notchIslandRowScale`); 1 beside a
    /// real notch.
    var scale: CGFloat = 1

    static let maxWidth: CGFloat = 170
    /// Narrower than this, a name says too little to be worth the room.
    static let minimumWidth: CGFloat = 48

    var body: some View {
        Text(verbatim: name)
            .font(.system(size: 12 * scale, weight: .medium))
            .foregroundStyle(NotchIslandStyle.label)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// A drawn notch's or the pill's row with the lead session's name, in one
/// line: every piece at its own width, and the name (`IsName`) in what
/// `limit` leaves of the row. A name that would be cut below
/// `SessionName.minimumWidth` is left out (placed with no width, and
/// clipped) and the row is as short as without it. Laid out rather than
/// measured, like `NotchWings`: nothing goes up to the controller.
struct NamedRowLayout: Layout {
    /// Marks the name among the row's pieces.
    struct IsName: LayoutValueKey {
        static let defaultValue = false
    }

    var spacing: CGFloat
    /// The widest the row may be (twice `NotchIslandState.availableWing`,
    /// less the row's own insets); nil when nothing limits it.
    var limit: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: Self.total(widths(subviews), spacing: spacing), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(subviews)) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: bounds.height))
            if width > 0 { x += width + spacing }
        }
    }

    private func widths(_ subviews: Subviews) -> [CGFloat] {
        Self.widths(
            ideal: subviews.map { $0.sizeThatFits(.unspecified).width },
            name: subviews.firstIndex { $0[IsName.self] },
            spacing: spacing,
            limit: limit
        )
    }

    /// Each piece at its ideal width, but the name, which gets what is left
    /// under `limit` (never more than its own ideal width), or nothing when
    /// that would cut it below `SessionName.minimumWidth`; a name shorter
    /// than that shows whenever it fits whole.
    static func widths(ideal: [CGFloat], name: Int?, spacing: CGFloat, limit: CGFloat?) -> [CGFloat] {
        guard let name, ideal.indices.contains(name) else { return ideal }
        var widths = ideal
        widths[name] = 0
        let fitted = min(ideal[name], (limit ?? .infinity) - total(widths, spacing: spacing) - spacing)
        widths[name] = fitted >= min(ideal[name], SessionName.minimumWidth) ? fitted : 0
        return widths
    }

    /// The row's width: the pieces shown, `spacing` between them.
    static func total(_ widths: [CGFloat], spacing: CGFloat) -> CGFloat {
        let shown = widths.filter { $0 > 0 }
        return shown.reduce(0, +) + spacing * CGFloat(max(0, shown.count - 1))
    }
}

/// What the lead session is doing, as its row says it: "Working for 3m",
/// "Needs permission" in yellow, "Done just now"; cut short past
/// `maxWidth` in a long language, for the same window as the name.
struct SessionDetail: View {
    let row: NotchIslandModel.Sessions.Row

    static let maxWidth: CGFloat = 150

    var body: some View {
        Text(row.detail)
            .font(.system(size: 11))
            .foregroundStyle(row.status == .waiting ? Theme.islandWarning : NotchIslandStyle.reset)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: Self.maxWidth, alignment: .trailing)
            .accessibilityHidden(true)
    }
}
#endif
