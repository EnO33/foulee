@preconcurrency import BackgroundTasks
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
