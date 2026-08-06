import SwiftUI

/// Top-level container. Gates onboarding, shows the home screen once the user
/// has set their goals, and applies the chosen theme to the whole app.
/// Also keeps the walk-reminder schedule in sync with the prefs that
/// drive it (active days + window start + notifications toggle).
struct RootView: View {
    @State private var preferences: UserPreferences
    @Environment(\.scenePhase) private var scenePhase
    private let scheduler = WalkReminderScheduler()
    private let hydrationScheduler = HydrationReminderScheduler()

    /// Injectable defaults for the same reason `UserPreferences` takes them:
    /// a test can seed an install — one that finished the pre-#221 flow, say —
    /// in a clean suite and check which branch this view actually renders.
    /// Gating onboarding is the one thing here no test could reach before.
    init(defaults: UserDefaults = .standard) {
        _preferences = State(initialValue: UserPreferences(defaults: defaults))
    }

    var body: some View {
        Group {
            if preferences.hasCompletedOnboarding {
                HomeView()
            } else {
                OnboardingFlow(preferences: preferences) {
                    preferences.hasCompletedOnboarding = true
                }
            }
        }
        .preferredColorScheme(preferences.themeMode.colorScheme)
        .environment(preferences)
        .task(id: scheduleKey) { await syncReminders() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Ask for a background refresh so the widgets keep moving
                // while the app stays closed.
                FouleeApp.scheduleAppRefresh()
            case .active:
                // Re-sync hydration reminders on every foreground so the
                // standard daily grid is restored once "today's" drink is
                // stale — otherwise a glass logged yesterday leaves the
                // shifted (repeating) grid in place and the morning
                // reminders never come back. `scheduleKey` alone misses this
                // because it doesn't change on a day boundary.
                Task { await syncHydration() }
            default:
                break
            }
        }
    }

    /// Reschedule whenever any input that affects the notification schedule
    /// changes (onboarding done + active days + window start + toggle).
    private var scheduleKey: String {
        let days = preferences.activeDays.bitmask
        let start = preferences.walkWindowStart.rawMinutes
        let on = preferences.notificationsEnabled ? 1 : 0
        return "\(preferences.hasCompletedOnboarding):\(days):\(start):\(on):\(hydrationKey)"
    }

    /// Hydration inputs that change the reminder schedule.
    private var hydrationKey: String {
        let on = (preferences.hydrationEnabled && preferences.hydrationRemindersEnabled) ? 1 : 0
        let start = preferences.hydrationWindowStart.rawMinutes
        let end = preferences.hydrationWindowEnd.rawMinutes
        let interval = preferences.hydrationIntervalMinutes
        let snooze = preferences.hydrationSnoozeMinutes
        return "\(on):\(start):\(end):\(interval):\(snooze)"
    }

    private func syncReminders() async {
        guard preferences.hasCompletedOnboarding else { return }
        await scheduler.sync(with: preferences)
        await hydrationScheduler.sync(with: preferences)
    }

    private func syncHydration() async {
        guard preferences.hasCompletedOnboarding else { return }
        await hydrationScheduler.sync(with: preferences)
    }
}

#Preview {
    RootView()
}
