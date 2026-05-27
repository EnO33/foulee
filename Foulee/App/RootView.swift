import SwiftUI

/// Top-level container. Gates onboarding, hosts the tab nav once the user
/// has set their goals, and applies the chosen theme to the whole app.
/// Also keeps the walk-reminder schedule in sync with the prefs that
/// drive it (active days + window start + notifications toggle).
struct RootView: View {
    @State private var preferences = UserPreferences()
    private let scheduler = WalkReminderScheduler()

    var body: some View {
        Group {
            if preferences.hasCompletedOnboarding {
                RootTabView(preferences: preferences)
            } else {
                OnboardingFlow(preferences: preferences) {
                    preferences.hasCompletedOnboarding = true
                }
            }
        }
        .preferredColorScheme(preferences.themeMode.colorScheme)
        .environment(preferences)
        .task(id: scheduleKey) { await syncReminders() }
    }

    /// Reschedule whenever any input that affects the notification schedule
    /// changes (onboarding done + active days + window start + toggle).
    private var scheduleKey: String {
        let days = preferences.activeDays.bitmask
        let start = preferences.walkWindowStart.rawMinutes
        let on = preferences.notificationsEnabled ? 1 : 0
        return "\(preferences.hasCompletedOnboarding):\(days):\(start):\(on)"
    }

    private func syncReminders() async {
        guard preferences.hasCompletedOnboarding else { return }
        await scheduler.sync(with: preferences)
    }
}

#Preview {
    RootView()
}
