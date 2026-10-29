import Combine
import FouleeKit
import SwiftUI

/// Top-level container. Gates onboarding, shows the home screen once the user
/// has set their goals, and applies the chosen theme to the whole app.
/// Also keeps the walk-reminder schedule in sync with the prefs that
/// drive it (active days + window start + notifications toggle), and the
/// recap notifications with theirs (issue #344).
struct RootView: View {
    @State private var preferences: UserPreferences
    private let cloud: SettingsKeyValueStore?
    @Environment(\.scenePhase) private var scenePhase
    private let scheduler = WalkReminderScheduler()
    private let hydrationScheduler = HydrationReminderScheduler()
    private let recapScheduler = RecapReminderScheduler()

    /// Injectable defaults for the same reason `UserPreferences` takes them:
    /// a test can seed an install — one that finished the pre-#221 flow, say —
    /// in a clean suite and check which branch this view actually renders.
    /// Gating onboarding is the one thing here no test could reach before.
    init(defaults: UserDefaults = .standard, cloud: SettingsKeyValueStore? = nil) {
        _preferences = State(initialValue: UserPreferences(defaults: defaults, cloud: cloud))
        self.cloud = cloud
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
        // The settings and outing merges of the user's other iPhones (issues
        // #616, #617): at launch, then each time iCloud brings a change. The
        // notification comes on a background queue.
        .task { syncWithCloud() }
        .onReceive(
            NotificationCenter.default
                .publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
                .receive(on: DispatchQueue.main)
        ) { _ in syncWithCloud() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Ask for a background refresh so the widgets keep moving
                // while the app stays closed.
                FouleeApp.scheduleAppRefresh()
            case .active:
                // Re-sync every reminder on each foreground. Hydration needs
                // it so the standard daily grid is restored once "today's"
                // drink is stale — otherwise a glass logged yesterday leaves
                // the shifted (repeating) grid in place and the morning
                // reminders never come back; `scheduleKey` alone misses this
                // because it doesn't change on a day boundary. The others need
                // it since #394: permission granted from Réglages, or in iOS
                // Settings, changes no preference either, yet the schedule
                // must follow. Every sync replaces its requests: idempotent.
                Task { await syncReminders() }
            default:
                break
            }
        }
    }

    private func syncWithCloud() {
        preferences.syncWithCloud()
        if let cloud { OutingMergeStore.syncWithCloud(cloud) }
    }

    /// Reschedule whenever any input that affects the notification schedule
    /// changes (onboarding done + active days + window start + toggle).
    private var scheduleKey: String {
        let days = preferences.activeDays.bitmask
        let start = preferences.walkWindowStart.rawMinutes
        let on = preferences.notificationsEnabled ? 1 : 0
        let recap = preferences.recapNotificationsEnabled ? 1 : 0
        return "\(preferences.hasCompletedOnboarding):\(days):\(start):\(on):\(recap):\(hydrationKey)"
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
        await recapScheduler.sync(with: preferences)
    }
}

#Preview {
    RootView()
}
