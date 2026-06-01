import SwiftUI

/// Top-level tab container. A `TabView` renders only the **selected** screen
/// each frame (the previous design kept all three mounted and composited at
/// once, tripling the glass/shadow cost), while still preserving each tab's
/// state between visits — so there's no re-fetch on tab taps. The system tab
/// bar is hidden in favour of the custom `BottomNav`, and the shared
/// `Wallpaper` sits behind the transparent tab content.
struct RootTabView: View {
    @Bindable var preferences: UserPreferences
    @State private var activeTab: BottomNavTab = .today

    var body: some View {
        ZStack(alignment: .bottom) {
            Wallpaper()
            TabView(selection: $activeTab) {
                TodayScreen()
                    .tag(BottomNavTab.today)
                    .toolbar(.hidden, for: .tabBar)
                StatsScreen(preferences: preferences)
                    .tag(BottomNavTab.stats)
                    .toolbar(.hidden, for: .tabBar)
                SettingsScreen(preferences: preferences)
                    .tag(BottomNavTab.settings)
                    .toolbar(.hidden, for: .tabBar)
            }
            BottomNav(active: $activeTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
    }
}
