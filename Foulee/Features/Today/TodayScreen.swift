import Dependencies
import SwiftUI

/// Pre/post-walk dashboard. Content-only: the wallpaper + bottom nav are
/// provided by `RootTabView`. Data comes from `TodayStore`, which reads
/// HealthKit through the `healthKit` dependency.
struct TodayScreen: View {
    @State private var store = TodayStore()
    @State private var isWalking = false
    @State private var isShowingSummary = false

    @Environment(UserPreferences.self) private var preferences
    private let scheduler = WalkReminderScheduler()

    var body: some View {
        content
            .task { await store.bootstrap() }
            .fullScreenCover(isPresented: $isWalking) {
                ActiveWalkScreen(minutesGoal: store.minutesGoal) {
                    isWalking = false
                    Task { await store.refresh() }
                }
            }
            .sheet(isPresented: $isShowingSummary) {
                TodayWorkoutsSheet()
            }
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
                if let lastError = store.lastError {
                    errorBanner(message: lastError)
                        .padding(.horizontal, 20)
                }
                TodayHeroCard(
                    snapshot: snapshot,
                    notificationsEnabled: preferences.notificationsEnabled,
                    onPrimaryTap: { handlePrimaryTap(snapshot: snapshot) },
                    onSnooze: { interval in
                        Task { await scheduler.snooze(after: interval) }
                    },
                    onToggleNotifications: {
                        preferences.notificationsEnabled.toggle()
                    }
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
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(FouleeColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Données partiellement indisponibles")
                    .font(FouleeFont.footnote.weight(.semibold))
                Text(message)
                    .font(FouleeFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .fouleeGlass(cornerRadius: 16)
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

    /// "Démarrer la marche" → push the active walk sheet.
    /// "Voir le résumé" (already walked today) → present an in-app sheet
    /// listing all walking workouts HealthKit recorded today, regardless
    /// of source (Foulée, Forme, the Watch).
    private func handlePrimaryTap(snapshot: TodaySnapshot) {
        if snapshot.hasWalkedToday {
            isShowingSummary = true
        } else {
            isWalking = true
        }
    }
}

private struct TodayPreviewWithData: View {
    init() {
        prepareDependencies { $0.healthKit = .previewValue }
    }
    var body: some View {
        TodayScreen()
            .environment(UserPreferences(defaults: previewDefaults(suite: "preview-today-light")))
            .preferredColorScheme(.light)
    }
}

private struct TodayPreviewLoading: View {
    init() {
        prepareDependencies {
            $0.healthKit = HealthKitClient(
                isAvailable: { true },
                requestAuthorization: {
                    try await Task.sleep(for: .seconds(60))
                    return true
                },
                todayMetrics: { .zero },
                saveWalkingWorkout: { _ in },
                dailyMinutes: { _ in [] },
                recentWorkouts: { _ in [] }
            )
        }
    }
    var body: some View {
        TodayScreen()
            .environment(UserPreferences(defaults: previewDefaults(suite: "preview-today-loading")))
    }
}

private struct TodayPreviewDark: View {
    init() {
        prepareDependencies { $0.healthKit = .previewValue }
    }
    var body: some View {
        TodayScreen()
            .environment(UserPreferences(defaults: previewDefaults(suite: "preview-today-dark")))
            .preferredColorScheme(.dark)
    }
}

@MainActor
private func previewDefaults(suite: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

#Preview("With data") { TodayPreviewWithData() }
#Preview("Loading") { TodayPreviewLoading() }
#Preview("Dark") { TodayPreviewDark() }
