import SwiftUI

/// Top-level tab container. Owns the wallpaper + bottom nav and keeps
/// the three feature screens mounted simultaneously, flipping opacity
/// instead of swapping the view tree. This avoids destroying/recreating
/// each screen (and re-running their `.task` data fetches) on every tab
/// tap — what made the nav feel sluggish.
struct RootTabView: View {
    @Bindable var preferences: UserPreferences
    @State private var activeTab: BottomNavTab = .today

    var body: some View {
        ZStack(alignment: .bottom) {
            Wallpaper()
            screen(.today) { TodayScreen() }
            screen(.stats) { StatsScreen(preferences: preferences) }
            screen(.settings) { SettingsScreen(preferences: preferences) }
            BottomNav(active: $activeTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
        .animation(.easeOut(duration: 0.2), value: activeTab)
    }

    /// Wraps a feature screen in an `opacity` + `allowsHitTesting` pair
    /// keyed on whether it's the active tab. Inactive screens stay in
    /// the view tree (no re-fetch on next visit) but don't intercept
    /// touches.
    private func screen<Content: View>(
        _ tab: BottomNavTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isActive = activeTab == tab
        return content()
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
    }
}
