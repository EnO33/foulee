@preconcurrency import ActivityKit
@preconcurrency import BackgroundTasks
import Dependencies
import SwiftUI
import WidgetKit

@main
struct FouleeApp: App {
    /// Background app-refresh task: an extra wake source between Health
    /// background deliveries, so the widgets keep moving all day.
    static let refreshTaskID = "com.eno33.foulee.refresh"

    init() {
        // Handle hydration reminder action taps ("J'ai bu" / "Rappelle-moi"),
        // including when iOS launches the app in the background to do so.
        HydrationNotificationCenter.shared.configure()
        // BGTaskScheduler throws on double registration, and FouleeApp can be
        // constructed more than once (tests, previews) — register exactly once.
        _ = Self.registerAppRefreshOnce
        _ = Self.endOrphanedWalkActivitiesOnce
        _ = Self.startHealthObserversOnce
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }

    private static let registerAppRefreshOnce: Void = {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            scheduleAppRefresh() // chain the next wake
            let work = Task {
                await refreshWidgetSnapshotFromHealth()
                WidgetCenter.shared.reloadAllTimelines()
            }
            // Set the handler before awaiting the result, and complete the
            // task on every path — including expiration — so iOS doesn't
            // penalise future background grants for an un-completed task.
            task.expirationHandler = { work.cancel() }
            Task {
                _ = await work.value
                task.setTaskCompleted(success: !work.isCancelled)
            }
        }
    }()

    // Active-walk state lives in memory only, so any walk Live Activity
    // found at process start is an orphan left by a crash/force-quit —
    // without this it sits on the Lock Screen as "en cours" for hours.
    // Once-gated: SwiftUI can re-construct FouleeApp mid-walk, and a second
    // sweep would kill the legitimate live activity.
    private static let endOrphanedWalkActivitiesOnce: Void = {
        Task {
            for activity in Activity<WalkActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }()

    // A HealthKit background delivery can relaunch a *terminated* app with no
    // UI mounted, so TodayStore.bootstrap() (Today-tab .task) never runs on
    // that path and the wake would do nothing. Register the observers at
    // process start instead; bootstrap() keeps its own call and the closure's
    // one-shot lock dedupes — whichever runs first wins. Registering before
    // requestAuthorization is fine: unauthorized queries just return nothing,
    // and bootstrap still prompts on the first Today appearance.
    private static let startHealthObserversOnce: Void = {
        @Dependency(\.healthKit) var healthKit
        Task { await healthKit.enableBackgroundDelivery() }
    }()

    /// Ask iOS for a background refresh in ~2 h. Called when the app goes to
    /// the background; iOS decides the actual timing from usage patterns. This
    /// is only a safety net — HealthKit background delivery (hourly steps,
    /// immediate water/workouts) is the primary wake source — so a wide
    /// interval keeps it from competing with the widgets' own refresh budget.
    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
