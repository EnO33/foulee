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
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }()

    /// Ask iOS for a background refresh in ~30 min. Called when the app goes
    /// to the background; iOS decides the actual timing from usage patterns.
    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
