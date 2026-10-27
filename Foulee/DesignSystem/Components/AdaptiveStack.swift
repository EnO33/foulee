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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: count), spacing: spacing) {
            content
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
