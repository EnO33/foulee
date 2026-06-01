import Dependencies
import SwiftUI

/// Stats tab — segmented range, streak hero, chart, summary cards.
/// Content-only: wallpaper + nav from `RootTabView`.
struct StatsScreen: View {
    @Bindable var preferences: UserPreferences
    @State private var store = StatsStore()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                rangePicker
                    .padding(.horizontal, 20)
                StreakHeroCard(
                    currentStreak: store.currentStreak(
                        goalMinutes: preferences.minutesGoal,
                        activeDays: preferences.activeDays
                    ),
                    bestStreak: store.bestStreak(
                        goalMinutes: preferences.minutesGoal,
                        activeDays: preferences.activeDays
                    )
                )
                .padding(.horizontal, 20)
                StatsChartCard(
                    data: store.filteredHistory(),
                    goalMinutes: preferences.minutesGoal,
                    range: store.range
                )
                .padding(.horizontal, 20)
                summaryCards
                    .padding(.horizontal, 20)
            }
            .padding(.top, 60)
            .padding(.bottom, 120)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("STATISTIQUES")
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            Text("Ton activité")
                .font(FouleeFont.largeTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rangePicker: some View {
        Picker("Plage", selection: $store.range) {
            ForEach(StatsRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                icon: FouleeIcon.check,
                tint: FouleeColor.success,
                label: "MARCHES",
                value: "\(store.totalWalks(goalMinutes: preferences.minutesGoal))",
                sub: "sur \(store.range.label.lowercased())"
            )
            summaryCard(
                icon: FouleeIcon.timer,
                tint: FouleeColor.accentSecondary,
                label: "MOYENNE",
                value: "\(store.averageMinutes())",
                sub: "min / jour"
            )
        }
    }

    private func summaryCard(
        icon: String,
        tint: Color,
        label: String,
        value: String,
        sub: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(tint)
                Text(label)
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
            }
            Text(value)
                .font(FouleeFont.numeric(size: 30))
            Text(sub)
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .fouleeGlass(cornerRadius: 22)
    }
}

private struct StatsPreview: View {
    @State private var preferences = UserPreferences(
        defaults: UserDefaults(suiteName: "preview-stats")!
    )
    init() {
        prepareDependencies { $0.healthKit = .previewValue }
    }
    var body: some View {
        ZStack {
            Wallpaper()
            StatsScreen(preferences: preferences)
        }
    }
}

#Preview("Light") { StatsPreview().preferredColorScheme(.light) }
#Preview("Dark") { StatsPreview().preferredColorScheme(.dark) }
