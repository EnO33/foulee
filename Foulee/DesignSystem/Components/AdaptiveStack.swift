import SwiftUI

/// Side by side, stacked once text reaches the accessibility sizes (#371,
/// #597): beside a ring or a figure, text gets a column too narrow to hold a
/// word, and side-by-side figures shrink past reading.
struct AdaptiveStack<Content: View>: View {
    var stacked: VStackLayout
    var regular: HStackLayout
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(stacked) : AnyLayout(regular)
        layout { content }
    }
}

/// The grid counterpart of `AdaptiveStack`: fewer columns at the
/// accessibility sizes, where tiles side by side shrank their figures past
/// reading (#371).
struct AdaptiveGrid<Content: View>: View {
    var columns: Int
    var accessibilityColumns: Int
    var spacing: CGFloat
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let count = dynamicTypeSize.isAccessibilitySize ? accessibilityColumns : columns
        ColumnsLayout(columns: count, spacing: spacing) {
            content
        }
    }
}

/// Equal columns, filled row by row, each row as tall as its tallest cell and
/// every cell centred in its own: `LazyVGrid` with flexible columns, drawn
/// at once. A cell offered its row's height can take it, so tiles on one row
/// stay level when one of them wraps.
///
/// Not lazy on purpose (issue #658): the accessibility audit reads the texts
/// of a lazy grid as « Dynamic Type partially unsupported », though they grow
/// like any other. The grids here hold a handful of cells, which laziness
/// never saved anything on.
struct ColumnsLayout: Layout {
    var columns: Int
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let heights = rowHeights(of: subviews, columnWidth: columnWidth(in: width))
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = columnWidth(in: bounds.width)
        let heights = rowHeights(of: subviews, columnWidth: width)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                let center = CGPoint(
                    x: bounds.minX + CGFloat(column) * (width + spacing) + width / 2,
                    y: y + height / 2
                )
                subviews[index].place(at: center, anchor: .center, proposal: ProposedViewSize(width: width, height: height))
            }
            y += height + spacing
        }
    }

    private func columnWidth(in width: CGFloat) -> CGFloat {
        max((width - spacing * CGFloat(columns - 1)) / CGFloat(columns), 0)
    }

    private func rowHeights(of subviews: Subviews, columnWidth: CGFloat) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
                .max() ?? 0
        }
    }
}

extension View {
    /// Text that stops growing at the largest standard size (#597), for
    /// boxes that cannot grow with it: chart axes, a control's caption. What
    /// it caps must be stated at full size elsewhere on the screen, or offered
    /// through the large content viewer.
    func cappedTextSize() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
