import SwiftUI

/// Pre/post-walk dashboard. Today shows: greeting + hero card + streak/weather
/// row + stats grid + week bars + floating bottom nav.
///
/// Static for now: the snapshot is a mock and the "Démarrer la marche" button
/// just flips between pending and completed states. PR#4 swaps the mock for
/// HealthKit-backed data; PR#5 wires the active walk session.
struct TodayScreen: View {
    @State private var snapshot: TodaySnapshot = .mockPending
    @State private var activeTab: BottomNavTab = .today

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: snapshot.date).uppercased()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Wallpaper()
            content
            BottomNav(active: $activeTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                TodayHeroCard(
                    snapshot: snapshot,
                    onPrimaryTap: toggleSnapshot,
                    onReminderTap: {}
                )
                .padding(.horizontal, 20)
                .padding(.top, 4)
                TodayStreakWeatherRow(snapshot: snapshot)
                    .padding(.horizontal, 20)
                TodayStatsGrid(snapshot: snapshot)
                    .padding(.horizontal, 20)
                TodayWeekBars(snapshot: snapshot)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 120)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formattedDate)
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            Text("Aujourd'hui")
                .font(FouleeFont.largeTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleSnapshot() {
        snapshot = snapshot.hasWalkedToday ? .mockPending : .mockCompleted
    }
}

#Preview("Pending") {
    TodayScreen()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    TodayScreen()
        .preferredColorScheme(.dark)
}
