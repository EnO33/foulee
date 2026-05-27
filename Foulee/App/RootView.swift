import SwiftUI

/// Gates the rest of the app on `UserPreferences.hasCompletedOnboarding`
/// and keeps the walk-reminder notification schedule in sync with the
/// active days + window start that the user picked.
struct RootView: View {
    @State private var preferences = UserPreferences()
    private let scheduler = WalkReminderScheduler()

    var body: some View {
        Group {
            if preferences.hasCompletedOnboarding {
                TodayScreen()
            } else {
                OnboardingFlow(preferences: preferences) {
                    preferences.hasCompletedOnboarding = true
                }
            }
        }
        .environment(preferences)
        .task(id: scheduleKey) { await syncReminders() }
    }

    /// Reschedule whenever any input that affects the notification schedule
    /// changes (onboarding done + active days + window start time).
    private var scheduleKey: String {
        let days = preferences.activeDays.bitmask
        let start = preferences.walkWindowStart.rawMinutes
        return "\(preferences.hasCompletedOnboarding):\(days):\(start)"
    }

    private func syncReminders() async {
        guard preferences.hasCompletedOnboarding else { return }
        await scheduler.sync(with: preferences)
    }
}

#Preview {
    RootView()
}
