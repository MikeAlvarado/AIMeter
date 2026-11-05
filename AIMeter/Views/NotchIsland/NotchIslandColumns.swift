#if os(macOS)
import SwiftUI

/// Where a view of `IslandColumns` goes: across the whole width, or in one
/// of an account's cells (`of` of them on its line): its figures, the
/// separator before them, or the bar under them.
nonisolated enum IslandCell: Equatable {
    case span
    case segment(Int, of: Int)
    case separator(Int, of: Int)
    case bar(Int, of: Int)
}

nonisolated private struct IslandCellKey: LayoutValueKey {
    static let defaultValue = IslandCell.span
}

nonisolated private struct IslandLineKey: LayoutValueKey {
    static let defaultValue = 0
}

extension View {
    /// Puts the view in `IslandColumns`' line `line`, as `cell`.
    func islandCell(_ cell: IslandCell, line: Int) -> some View {
        layoutValue(key: IslandCellKey.self, value: cell).layoutValue(key: IslandLineKey.self, value: line)
    }
}

/// The expanded island's account lines, stacked top to bottom (by their
/// `islandCell` line): a span line across the whole width, and an
/// account's figures in cells of one width that share the line edge to
/// edge with one gap between them, so its bars are equally wide and
/// equally spaced whether it reports two windows or three (Mike,
/// 2026-11-05). Its ideal width is the narrowest that gives every cell
/// its widest figure, what `ViewThatFits` measures to pick a size;
/// offered more, the cells grow; offered less, it keeps its ideal width
/// (the countdown in place of the clock time is there for that).
nonisolated struct IslandColumns: Layout {
    /// The lines one account can take: divider, header, figures, bars,
    /// status line.
    static let linesPerAccount = 5

    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let metrics = Metrics(subviews: subviews, gap: gap)
        let width = metrics.width(offered: proposal.width)
        let height = lines(of: subviews).reduce(0) { $0 + height(of: $1, in: subviews, metrics: metrics, width: width) }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let metrics = Metrics(subviews: subviews, gap: gap)
        let width = metrics.width(offered: bounds.width)
        var y = bounds.minY
        for line in lines(of: subviews) {
            for index in line {
                let subview = subviews[index]
                switch subview[IslandCellKey.self] {
                case .span:
                    subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: width, height: nil))
                case .segment(let cell, let count):
                    subview.place(at: CGPoint(x: bounds.minX + metrics.cellX(cell, of: count, width: width), y: y), proposal: .unspecified)
                case .separator(let cell, let count):
                    subview.place(at: CGPoint(x: bounds.minX + metrics.separatorX(cell, of: count, width: width), y: y), proposal: .unspecified)
                case .bar(let cell, let count):
                    subview.place(
                        at: CGPoint(x: bounds.minX + metrics.cellX(cell, of: count, width: width), y: y),
                        proposal: ProposedViewSize(width: metrics.cellWidth(of: count, width: width), height: nil)
                    )
                }
            }
            y += height(of: line, in: subviews, metrics: metrics, width: width)
        }
    }

    /// The subviews' indices by line, the lines in order.
    private func lines(of subviews: Subviews) -> [[Int]] {
        Dictionary(grouping: subviews.indices) { subviews[$0][IslandLineKey.self] }
            .sorted { $0.key < $1.key }
            .map(\.value)
    }

    private func height(of line: [Int], in subviews: Subviews, metrics: Metrics, width: CGFloat) -> CGFloat {
        line.map { index -> CGFloat in
            let subview = subviews[index]
            switch subview[IslandCellKey.self] {
            case .span: return subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            case .segment, .separator: return subview.sizeThatFits(.unspecified).height
            case .bar(_, let count): return subview.sizeThatFits(ProposedViewSize(width: metrics.cellWidth(of: count, width: width), height: nil)).height
            }
        }.max() ?? 0
    }

    /// The widest figure a cell holds and the separator's width, from
    /// which every line's cells are laid out.
    struct Metrics {
        /// The widest content of a cell on a line of `count` cells, by count.
        var widest: [Int: CGFloat]
        var separatorWidth: CGFloat
        let gap: CGFloat

        init(subviews: Subviews, gap: CGFloat) {
            var widest: [Int: CGFloat] = [:]
            var separatorWidth: CGFloat = 0
            for subview in subviews {
                switch subview[IslandCellKey.self] {
                case .segment(_, let count):
                    widest[count] = max(widest[count] ?? 0, subview.sizeThatFits(.unspecified).width)
                case .separator:
                    separatorWidth = max(separatorWidth, subview.sizeThatFits(.unspecified).width)
                default:
                    break
                }
            }
            self.init(widest: widest, separatorWidth: separatorWidth, gap: gap)
        }

        init(widest: [Int: CGFloat], separatorWidth: CGFloat, gap: CGFloat) {
            self.widest = widest
            self.separatorWidth = separatorWidth
            self.gap = gap
        }

        /// Between two cells: a gap, the separator, a gap.
        private var between: CGFloat { separatorWidth + 2 * gap }

        /// The narrowest width that gives every cell its widest content.
        var ideal: CGFloat {
            widest.map { count, width in CGFloat(count) * width + CGFloat(count - 1) * between }.max() ?? 0
        }

        /// What is offered when that is more than the ideal, else the ideal.
        func width(offered: CGFloat?) -> CGFloat {
            guard let offered, offered.isFinite, offered > ideal else { return ideal }
            return offered
        }

        /// The width of each of `count` cells sharing `width`.
        func cellWidth(of count: Int, width: CGFloat) -> CGFloat {
            guard count > 0 else { return width }
            return (width - CGFloat(count - 1) * between) / CGFloat(count)
        }

        func cellX(_ cell: Int, of count: Int, width: CGFloat) -> CGFloat {
            CGFloat(cell) * (cellWidth(of: count, width: width) + between)
        }

        /// The separator before `cell`, in the middle of the space between.
        func separatorX(_ cell: Int, of count: Int, width: CGFloat) -> CGFloat {
            cellX(cell, of: count, width: width) - gap - separatorWidth
        }
    }
}
#endif
