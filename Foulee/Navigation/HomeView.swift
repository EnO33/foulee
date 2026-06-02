import SwiftUI

/// App home: the shared `Wallpaper` behind the `TodayScreen`. There's no tab
/// bar — Settings is reached from the profile button in the Today header, and
/// per-metric stats open by tapping the cards.
struct HomeView: View {
    var body: some View {
        ZStack {
            Wallpaper()
            TodayScreen()
        }
    }
}
