import SwiftUI

/// A screen's main action, held at the bottom while the rest scrolls
/// (ADR 0008).
///
/// « Démarrer » used to sit at the end of the home's scroll view, under the
/// streak, the four tiles and the hydration card: the one thing the screen is
/// for was the last thing reached. Pinned here, it is on screen from the first
/// glance, whatever the text size.
///
/// **An overlay, not a `safeAreaInset`** (issue #440). The inset shrank the
/// scroll view to the space above the button, and on watchOS the home stopped
/// scrolling altogether. Over the scroll view, the button leaves it whole: the
/// content scrolls beneath, and a bottom margin of the button's height lets
/// the last row come up clear of it.
///
/// Not a toolbar item either: watchOS draws its bottom-bar buttons round and
/// glyph-only, and these are the app's capsules. The small control size keeps
/// the capsule to a sixth of the screen, and a fade to black, rather than an
/// opaque block, keeps the rows passing beneath readable to the last moment.
extension View {
    func pinnedAction<Action: View>(@ViewBuilder _ action: () -> Action) -> some View {
        modifier(WatchPinnedAction(action: action()))
    }
}

private struct WatchPinnedAction<Action: View>: ViewModifier {
    let action: Action

    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, height, for: .scrollContent)
            .overlay(alignment: .bottom) {
                action
                    .controlSize(.small)
                    .padding(.horizontal, 2)
                    .padding(.top, 14)
                    .background(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .center)
                            .ignoresSafeArea(edges: .bottom)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            }
    }
}
