import SwiftUI

/// Top-level container — for now just hosts the Today screen.
/// Tab switching is wired in PR#8 (Stats) and PR#10 (Settings).
struct RootView: View {
    var body: some View {
        TodayScreen()
    }
}

#Preview {
    RootView()
}
