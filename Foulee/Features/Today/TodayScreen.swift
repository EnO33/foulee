import Dependencies
import SwiftUI

/// Pre/post-walk dashboard. Hosts the wallpaper, a scrollable column of
/// cards and the floating bottom nav. Data comes from `TodayStore`, which
/// reads HealthKit through the `healthKit` dependency.
struct TodayScreen: View {
    @State private var store = TodayStore()
    @State private var activeTab: BottomNavTab = .today

    var body: some View {
        ZStack(alignment: .bottom) {
            Wallpaper()
            content
            BottomNav(active: $activeTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
        .task { await store.bootstrap() }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = store.snapshot {
            loaded(snapshot: snapshot)
        } else {
            placeholder
        }
    }

    private func loaded(snapshot: TodaySnapshot) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                header(date: snapshot.date)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                TodayHeroCard(
                    snapshot: snapshot,
                    onPrimaryTap: { Task { await store.refresh() } },
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
        .refreshable { await store.refresh() }
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(FouleeColor.accentMid)
            Text("Connexion à Santé…")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
            if let lastError = store.lastError {
                Text(lastError)
                    .font(FouleeFont.caption)
                    .foregroundStyle(FouleeColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private func header(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formatted(date: date))
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            Text("Aujourd'hui")
                .font(FouleeFont.largeTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date).uppercased()
    }
}

#Preview("With data") {
    _ = prepareDependencies { $0.healthKit = .previewValue }
    return TodayScreen()
        .preferredColorScheme(.light)
}

#Preview("Loading") {
    _ = prepareDependencies {
        $0.healthKit = HealthKitClient(
            isAvailable: { true },
            requestAuthorization: {
                try await Task.sleep(for: .seconds(60))
                return true
            },
            todayMetrics: { .zero }
        )
    }
    return TodayScreen()
}

#Preview("Dark") {
    _ = prepareDependencies { $0.healthKit = .previewValue }
    return TodayScreen()
        .preferredColorScheme(.dark)
}
