import SwiftUI

/// A screen's main action, held at the bottom while the rest scrolls
/// (ADR 0008).
///
/// « Démarrer » used to sit at the end of the home's scroll view, under the
/// streak, the four tiles and the hydration card: the one thing the screen is
/// for was the last thing reached. Pinned here, it is on screen from the first
/// glance, whatever the text size.
///
/// A `safeAreaInset` rather than a toolbar item: watchOS draws its bottom-bar
/// buttons in its own style, round and glyph-only, and these are the app's
/// full-width capsules. The scroll view stops short of the inset, so its last
/// row still clears the button; the background keeps the rows that scroll
/// beneath it from showing round its corners.
extension View {
    func pinnedAction<Action: View>(@ViewBuilder _ action: () -> Action) -> some View {
        safeAreaInset(edge: .bottom, spacing: 4) {
            action()
                .padding(.horizontal, 2)
                .background(.background)
        }
    }
}
