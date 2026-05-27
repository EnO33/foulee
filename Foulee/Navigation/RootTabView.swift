import SwiftUI

/// Top-level tab container. Owns the wallpaper + bottom nav and swaps the
/// active screen below. Each feature screen is now content-only — no
/// wallpaper, no nav — which makes them embeddable anywhere.
struct RootTabView: View {
    @Bindable var preferences: UserPreferences
    @State private var activeTab: BottomNavTab = .today

    var body: some View {
        ZStack(alignment: .bottom) {
            Wallpaper()
            content
                .id(activeTab)
                .transition(.opacity)
            BottomNav(active: $activeTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
        .animation(.easeOut(duration: 0.2), value: activeTab)
    }

    @ViewBuilder
    private var content: some View {
        switch activeTab {
        case .today: TodayScreen()
        case .stats: StatsScreen(preferences: preferences)
        case .settings: SettingsScreen(preferences: preferences)
        }
    }
}
