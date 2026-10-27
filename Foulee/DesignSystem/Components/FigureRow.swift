import SwiftUI

/// Figures side by side, split by thin rules — or one under the other at the
/// accessibility sizes (#408, #597), where a third of the width cut « Moyenne »
/// mid-word.
struct FigureRow<Content: View>: View {
    var spacing: CGFloat = 0
    var ruleHeight: CGFloat = 34
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 14) { content }
        } else {
            HStack(spacing: spacing) {
                Group(subviews: content) { figures in
                    ForEach(figures) { figure in
                        if figure.id != figures.first?.id { rule }
                        figure
                    }
                }
            }
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.25))
            .frame(width: 1, height: ruleHeight)
    }
}
