import SwiftUI

/// Top-level container. Gates onboarding, shows the home screen once the user
/// has set their goals, and applies the chosen theme to the whole app.
/// Also keeps the walk-reminder schedule in sync with the prefs that
/// drive it (active days + window start + notifications toggle).
struct RootView: View {
    @State private var preferences = UserPreferences()
    @Environment(\.scenePhase) private var scenePhase
    private let scheduler = WalkReminderScheduler()
    private let hydrationScheduler = HydrationReminderScheduler()

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
            // Ask for a background refresh so the widgets keep moving while
            // the app stays closed.
            if phase == .background { FouleeApp.scheduleAppRefresh() }
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
}

#Preview {
    RootView()
}
