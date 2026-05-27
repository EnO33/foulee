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
        case .stats: StatsPlaceholderScreen()
        case .settings: SettingsScreen(preferences: preferences)
        }
    }
}

/// Holding place until PR#8 ships the real Stats screen.
struct StatsPlaceholderScreen: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: FouleeIcon.calendar)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(FouleeColor.accentMid)
            Text("Statistiques bientôt")
                .font(FouleeFont.title3)
            Text("Tes séries et l'évolution des marches arrivent dans la prochaine version.")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
