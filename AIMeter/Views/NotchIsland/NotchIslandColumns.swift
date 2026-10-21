#if os(macOS)
import SwiftUI

/// Where a view of `IslandColumns` goes: across the whole width, or in a
/// column (a figure, the bar under it, or the separator before it).
nonisolated enum IslandCell: Equatable {
    case span
    case segment(Int)
    case separator(Int)
    case bar(Int)
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

/// The expanded island's columns: lines stacked top to bottom (by their
/// `islandCell` line), a span line across the whole width, the others in
/// columns as wide as their widest figure. Its ideal width is the columns
/// with `minimumGap` either side of each separator, what `ViewThatFits`
/// measures to pick a size; offered more, the separators share the extra
/// evenly, so the last column ends at the right edge; offered less, it
/// keeps its ideal width (the smaller sizes are there for that).
nonisolated struct IslandColumns: Layout {
    /// The lines one account can take: divider, header, figures, bars,
    /// status line.
    static let linesPerAccount = 5

    let columns: Int
    let minimumGap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let metrics = Metrics(columns: columns, subviews: subviews)
        let width = metrics.width(offered: proposal.width, minimumGap: minimumGap)
        let height = lines(of: subviews).reduce(0) { $0 + height(of: $1, in: subviews, metrics: metrics, width: width) }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let metrics = Metrics(columns: columns, subviews: subviews)
        let width = metrics.width(offered: bounds.width, minimumGap: minimumGap)
        let x = metrics.columnX(width: width, minimumGap: minimumGap)
        var y = bounds.minY
        for line in lines(of: subviews) {
            for index in line {
                let subview = subviews[index]
                switch subview[IslandCellKey.self] {
                case .span:
                    subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: width, height: nil))
                case .segment(let column):
                    subview.place(at: CGPoint(x: bounds.minX + x.columns[column], y: y), proposal: .unspecified)
                case .separator(let column):
                    subview.place(at: CGPoint(x: bounds.minX + x.separators[column], y: y), proposal: .unspecified)
                case .bar(let column):
                    subview.place(
                        at: CGPoint(x: bounds.minX + x.columns[column], y: y),
                        proposal: ProposedViewSize(width: metrics.columnWidths[column], height: nil)
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
            case .bar(let column): return subview.sizeThatFits(ProposedViewSize(width: metrics.columnWidths[column], height: nil)).height
            }
        }.max() ?? 0
    }

    /// The columns' widths and the separators', from the figures' own.
    struct Metrics {
        var columnWidths: [CGFloat]
        var separatorWidth: CGFloat = 0

        init(columns: Int, subviews: Subviews) {
            columnWidths = Array(repeating: 0, count: columns)
            for subview in subviews {
                switch subview[IslandCellKey.self] {
                case .segment(let column) where columnWidths.indices.contains(column):
                    columnWidths[column] = max(columnWidths[column], subview.sizeThatFits(.unspecified).width)
                case .separator:
                    separatorWidth = max(separatorWidth, subview.sizeThatFits(.unspecified).width)
                default:
                    break
                }
            }
        }

        init(columnWidths: [CGFloat], separatorWidth: CGFloat) {
            self.columnWidths = columnWidths
            self.separatorWidth = separatorWidth
        }

        /// The figures and the separators, no gap.
        var fixed: CGFloat {
            columnWidths.reduce(0, +) + separatorWidth * CGFloat(max(0, columnWidths.count - 1))
        }

        /// The gaps there are: one either side of each separator.
        var gaps: Int { 2 * max(0, columnWidths.count - 1) }

        func ideal(minimumGap: CGFloat) -> CGFloat {
            fixed + CGFloat(gaps) * minimumGap
        }

        /// The width taken: what is offered when that is more than the
        /// ideal (the gaps grow), else the ideal.
        func width(offered: CGFloat?, minimumGap: CGFloat) -> CGFloat {
            let ideal = ideal(minimumGap: minimumGap)
            guard let offered, offered.isFinite, offered > ideal else { return ideal }
            return offered
        }

        /// Where each column and each separator starts, for `width`.
        func columnX(width: CGFloat, minimumGap: CGFloat) -> (columns: [CGFloat], separators: [CGFloat]) {
            let gap = gaps > 0 ? max(minimumGap, (width - fixed) / CGFloat(gaps)) : 0
            var columns: [CGFloat] = []
            var separators: [CGFloat] = []
            var x: CGFloat = 0
            for (index, columnWidth) in columnWidths.enumerated() {
                if index > 0 {
                    x += gap
                    separators.append(x)
                    x += separatorWidth + gap
                } else {
                    separators.append(0)
                }
                columns.append(x)
                x += columnWidth
            }
            return (columns, separators)
        }
    }
}
#endif
