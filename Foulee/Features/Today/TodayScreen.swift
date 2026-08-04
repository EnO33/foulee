import Dependencies
import SwiftUI
import UIKit

/// Pre/post-walk dashboard and the app's home. Content-only: the wallpaper is
/// provided by `HomeView`. Data comes from `TodayStore`, which reads HealthKit
/// through the `healthKit` dependency. Settings open from the profile button.
struct TodayScreen: View {
    @State private var store = TodayStore()
    @State private var hydration = HydrationStore()
    @State private var isWalking = false
    @State private var isShowingSummary = false
    @State private var isShowingSettings = false
    @State private var selectedMetric: WalkMetric?
    @State private var isShowingWeather = false
    @State private var isShowingStreak = false
    @State private var scrollToHydration = false

    @Environment(UserPreferences.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.openURL) private var openURL
    private let scheduler = WalkReminderScheduler()

    /// The app theme, applied to every modal — sheets/covers don't inherit the
    /// root `.preferredColorScheme`, so without this they'd render in the
    /// system appearance and ignore the user's Clair/Sombre choice. `.system`
    /// is resolved to the live system scheme so we never pass `nil` (which
    /// fails to reset an already-dark sheet back to light).
    private var preferredScheme: ColorScheme {
        preferences.themeMode.colorScheme ?? systemColorScheme
    }

    var body: some View {
        content
            .task { await store.bootstrap() }
            .task {
                hydration.startObserving()
                await hydration.refresh()
            }
            .task(id: todayPreferencesKey(preferences)) {
                // Push the user's current goals + walk-window into the
                // store on first appear and whenever they change.
                // `apply` re-derives the snapshot from cached history
                // so the ring, streak and countdown update immediately.
                store.apply(preferences: preferences)
            }
            // `.task` runs once; re-query whenever the app returns to the
            // foreground so the dashboard isn't stuck on stale (or zero)
            // values after the user walked and came back.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await store.refresh() }
                    Task { await hydration.refresh() }
                }
            }
            .onChange(of: preferences.hydrationEnabled) { _, enabled in
                // Turning hydration on prompts for Health (water) access.
                if enabled { Task { await hydration.enable() } }
            }
            .overlay(alignment: .top) {
                // "C'est compté" feedback after a notification action tap.
                HydrationActionToast { Task { await hydration.refresh() } }
            }
            .onOpenURL { url in
                // foulee://hydration — widget tap lands on the hydration card.
                if url.host() == "hydration" { scrollToHydration = true }
            }
            .fullScreenCover(isPresented: $isWalking) {
                ActiveWalkScreen(minutesGoal: store.minutesGoal) { session in
                    isWalking = false
                    Task { await store.registerFinishedWalk(session) }
                }
                .preferredColorScheme(preferredScheme)
            }
            .sheet(
                isPresented: $isShowingSummary,
                onDismiss: { Task { await store.refresh() } },
                content: {
                    TodayWorkoutsSheet()
                        .preferredColorScheme(preferredScheme)
                }
            )
            .sheet(
                item: $selectedMetric,
                onDismiss: { Task { await store.refresh() } },
                content: { metric in
                    MetricStatsScreen(metric: metric, dailyGoal: dailyGoal(for: metric)) {
                        selectedMetric = nil
                    }
                    .preferredColorScheme(preferredScheme)
                }
            )
            .sheet(isPresented: $isShowingWeather) {
                if let weather = store.snapshot?.weather {
                    WeatherDetailSheet(weather: weather) { isShowingWeather = false }
                        .preferredColorScheme(preferredScheme)
                }
            }
            .sheet(isPresented: $isShowingStreak) {
                StreakCalendarSheet(
                    goalMinutes: store.minutesGoal,
                    goalSteps: preferences.stepsGoal,
                    activeDays: preferences.activeDays
                ) { isShowingStreak = false }
                .preferredColorScheme(preferredScheme)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsScreen(preferences: preferences)
                    .overlay(alignment: .topTrailing) {
                        Button { isShowingSettings = false } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.primary)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.pressable)
                        .padding(20)
                        .accessibilityLabel("Fermer")
                    }
                    .presentationBackground { SheetBackground() }
                    .preferredColorScheme(preferredScheme)
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

    private func heroCard(snapshot: TodaySnapshot) -> some View {
        TodayHeroCard(
            snapshot: snapshot,
            notificationsEnabled: preferences.notificationsEnabled,
            notificationsDenied: store.notificationsAuthorizationStatus == .denied,
            onStart: { startWalk() },
            onSummary: { isShowingSummary = true },
            onSnooze: { interval in
                Task { await scheduler.snooze(after: interval) }
            },
            onToggleNotifications: {
                preferences.notificationsEnabled.toggle()
            },
            onOpenNotificationSettings: {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
        )
    }

    private func loaded(snapshot: TodaySnapshot) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 12) {
                header(date: snapshot.date)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                // One card at most, most-explanatory first. A failed fetch
                // outranks both hints — a day can perfectly well hold data
                // *and* a failed fetch, and only the banner explains why the
                // numbers may be wrong.
                if store.lastError != nil {
                    TodayErrorBanner()
                        .padding(.horizontal, 20)
                } else if store.showsGarminSyncHint {
                    // Before the generic empty state: telling a Garmin user to
                    // "faire quelques pas" when the real gap is an unsynced
                    // Garmin Connect would send them nowhere.
                    GarminSyncHintCard()
                        .padding(.horizontal, 20)
                } else if snapshot.hasNoActivity {
                    TodayEmptyStateCard()
                        .padding(.horizontal, 20)
                }
                heroCard(snapshot: snapshot)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                TodayStreakWeatherRow(
                    snapshot: snapshot,
                    onStreakTap: { isShowingStreak = true },
                    onWeatherTap: { isShowingWeather = true }
                )
                .padding(.horizontal, 20)
                TodayStatsGrid(snapshot: snapshot) { selectedMetric = $0 }
                    .padding(.horizontal, 20)
                HydrationHomeCard(preferences: preferences, store: hydration)
                    .id("hydrationCard")
                TodayFooter(snapshot: snapshot, activeDays: preferences.activeDays) {
                    isShowingSummary = true
                }
            }
            .padding(.bottom, 40)
        }
        .refreshable { await store.refresh() }
        .modifier(HydrationDeepLinkScroll(proxy: proxy, pending: $scrollToHydration))
        }
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

    private func header(date: Date) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatted(date: date))
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                Text("Aujourd'hui")
                    .font(FouleeFont.largeTitle)
            }
            Spacer()
            Button { isShowingSettings = true } label: {
                Image(systemName: "person.crop.circle")
                    .scaledSystemFont(size: 32)
                    .foregroundStyle(FouleeColor.accentMid)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Profil et réglages")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private func formatted(date: Date) -> String {
        Self.headerDateFormatter.string(from: date).uppercased()
    }

    /// Push the active walk sheet. Available from the hero even once today's
    /// goal is met (the card then also offers "Voir le résumé"), so a second
    /// walk can always be started.
    private func startWalk() {
        // Capture today's totals now so the post-walk overlay lands on the
        // right baseline (see TodayStore.registerFinishedWalk).
        store.walkWillStart()
        isWalking = true
    }

    /// Only steps + minutes have a daily goal to draw on the stats chart.
    private func dailyGoal(for metric: WalkMetric) -> Double? {
        switch metric {
        case .steps: Double(store.stepsGoal)
        case .minutes: Double(store.minutesGoal)
        case .distance, .calories: nil
        }
    }
}

/// Week bars (tap → walk history) + the Apple Weather attribution required by
/// Guideline 5.2.5. File-scope to keep `TodayScreen` within lint bounds.
private struct TodayFooter: View {
    let snapshot: TodaySnapshot
    let activeDays: Set<Weekday>
    var onSummary: () -> Void

    var body: some View {
        Button(action: onSummary) {
            TodayWeekBars(snapshot: snapshot, activeDays: activeDays)
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, 20)
        .accessibilityHint("Voir l'historique des marches")
        if snapshot.weather.isAvailable {
            WeatherAttributionView()
                .padding(.horizontal, 20)
                .padding(.top, 4)
        }
    }
}

private struct TodayErrorBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(FouleeColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Données partiellement indisponibles")
                    .font(FouleeFont.footnote.weight(.semibold))
                Text("Vérifie l'accès à Santé dans Réglages, puis réessaie.")
                    .font(FouleeFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .fouleeGlass(cornerRadius: 16)
    }
}

/// Shown on a fresh install / denied access / no activity yet, instead of
/// a screen full of muted zeros.
private struct TodayEmptyStateCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: FouleeIcon.walkMotion)
                .scaledSystemFont(size: 40, weight: .semibold)
                .foregroundStyle(FouleeColor.accentMid)
            Text("Pas encore de données")
                .font(FouleeFont.headline)
            Text("Connecte Santé et fais quelques pas — ta marche du midi s'affichera ici.")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: "x-apple-health://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Ouvrir Santé")
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(FouleeColor.accentMid)
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .fouleeGlass(cornerRadius: 24)
    }
}

/// Scrolls the home to the hydration card when the `foulee://hydration` deep
/// link fires (widget tap). Handles both orders: URL before the content is
/// mounted (cold launch → `onAppear`) and after (warm open → `onChange`).
private struct HydrationDeepLinkScroll: ViewModifier {
    let proxy: ScrollViewProxy
    @Binding var pending: Bool

    func body(content: Content) -> some View {
        content
            .onAppear(perform: scrollIfPending)
            .onChange(of: pending) { _, _ in scrollIfPending() }
    }

    private func scrollIfPending() {
        guard pending else { return }
        pending = false
        // Slight delay so the freshly mounted scroll content has laid out.
        // No stored handle: a repeat deep link just scrolls to the same card,
        // so a stale fire is harmless and cancellation would be dead weight.
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation { proxy.scrollTo("hydrationCard", anchor: .center) }
        }
    }
}

/// Single value that flips whenever any preference the Today store reads
/// changes — drives the `.task(id:)` re-sync. File-scope so it stays out of
/// the view's body-length budget.
@MainActor
private func todayPreferencesKey(_ preferences: UserPreferences) -> String {
    let goals = "\(preferences.stepsGoal)-\(preferences.minutesGoal)"
    let window = "\(preferences.walkWindowStart.rawMinutes)-\(preferences.activeDays.bitmask)"
    let hydration = "\(preferences.hydrationEnabled)-\(preferences.hydrationGoalML)-\(preferences.hydrationGlassML)"
    return "\(goals)-\(window)-\(hydration)"
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
                requestAuthorization: {
                    try await Task.sleep(for: .seconds(60))
                    return true
                },
                todayMetrics: { .zero },
                saveWalkingWorkout: { _ in },
                dailyMinutes: { _ in [] },
                recentWorkouts: { _ in [] },
                workoutDetail: { summary in
                    WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
                }
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
