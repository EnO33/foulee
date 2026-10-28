import SwiftUI
import Testing
@testable import Foulee

/// The grid that replaced `LazyVGrid` under `AdaptiveGrid` and the Bilan's
/// month (issue #658) must lay cells out as it did: equal columns, rows as
/// tall as their tallest cell, the spacing between them.
@Suite("Columns layout")
@MainActor
struct ColumnsLayoutTests {
    @Test("Rows take their tallest cell's height, with the spacing between them")
    func rowsTakeTheirTallestCell() {
        let size = measure(width: 210) {
            ColumnsLayout(columns: 2, spacing: 10) {
                Color.clear.frame(height: 20)
                Color.clear.frame(height: 30)
                Color.clear.frame(height: 25)
            }
        }
        #expect(size == CGSize(width: 210, height: 30 + 10 + 25))
    }

    /// A square is as tall as its column is wide: 7 columns in 288 pt with
    /// 6 pt between them leave 252 / 7 = 36.
    @Test("Each column gets an equal share of the width left by the spacing")
    func columnsShareTheWidth() {
        let size = measure(width: 288) {
            ColumnsLayout(columns: 7, spacing: 6) {
                ForEach(0..<7, id: \.self) { _ in Square { EmptyView() } }
            }
        }
        #expect(size == CGSize(width: 288, height: 36))
    }

    @Test("Nothing to lay out takes no height")
    func emptyTakesNoHeight() {
        let size = measure(width: 200) {
            ColumnsLayout(columns: 4, spacing: 8) { EmptyView() }
        }
        #expect(size.height == 0)
    }

    private func measure(width: CGFloat, @ViewBuilder _ content: () -> some View) -> CGSize {
        UIHostingController(rootView: content())
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

/// As tall as the width it is offered, which is what the test reads back.
private struct Square: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let side = proposal.width ?? 0
        return CGSize(width: side, height: side)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}
