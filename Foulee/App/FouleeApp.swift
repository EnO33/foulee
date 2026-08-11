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
        #if DEBUG
        // First statement on purpose, and DEBUG-only: `prepareDependencies`
        // must run before anything resolves a dependency, and a Release build
        // does not compile `ScreenshotMode` at all (issue #235). Without the
        // `-FouleeScreenshotMode` launch argument this is a no-op.
        ScreenshotMode.activateIfRequested()
        #endif
        // Handle hydration reminder action taps ("J'ai bu" / "Rappelle-moi"),
        // including when iOS launches the app in the background to do so.
        HydrationNotificationCenter.shared.configure()
        // BGTaskScheduler throws on double registration, and FouleeApp can be
        // constructed more than once (tests, previews) — register exactly once.
        _ = Self.registerAppRefreshOnce
        _ = Self.endOrphanedWalkActivitiesOnce
        _ = Self.startHealthObserversOnce
        _ = Self.startGarminConnectIQOnce
        _ = Self.startMirrorObserverOnce
    }

    var body: some Scene {
        WindowGroup {
            RootView(defaults: Self.preferencesDefaults)
        }
    }

    /// Where the app reads the user's preferences from — always `.standard`,
    /// except during a screenshot capture, which gets a throwaway suite so it
    /// can seed goals and a theme without touching the real install.
    private static var preferencesDefaults: UserDefaults {
        #if DEBUG
        ScreenshotMode.preferencesDefaults ?? .standard
        #else
        .standard
        #endif
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
    //
    // An app *update* lands on the same path — this is what bounds how long an
    // activity started by a previous build can survive the change of attributes
    // shape (#225): the first launch of the new binary, foreground or
    // background, ends it. It runs after the extension has had the chance to
    // re-render that activity, so the sweep is the cleanup and the tolerant
    // decode is what has to hold in the window — see
    // WalkActivityAttributes.init(from:), which is also explicit about which
    // half of that story is verified and which is reasoned.
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

    // Connect IQ has to be initialized at *process* start, not when a screen
    // appears: the point of the BLE state-restoration identifier is that iOS
    // relaunches the app in the background when the paired Garmin watch has
    // data, and on that path no UI is ever mounted. Re-registering the known
    // devices immediately is what makes the wake useful.
    //
    // Each decoded snapshot then goes to `GarminSnapshotIngestion`, which owns
    // the day-stamped overlay and the merge (#189). Nothing on this path ever
    // writes to HealthKit: Garmin Connect syncs the same day later, and a
    // sample written here would double-count it forever.
    private static let startGarminConnectIQOnce: Void = {
        @Dependency(\.garminConnectIQ) var garminConnectIQ
        garminConnectIQ.initialize()
        garminConnectIQ.startReceiving()
        Task { await GarminSnapshotIngestion.run(garminConnectIQ.snapshots()) }
    }()

    // A mirrored workout session (issue #277) arrives through
    // `HKHealthStore.workoutSessionMirroringStartHandler`, and HealthKit can
    // relaunch a *terminated* app to deliver one — on that path no UI is ever
    // mounted, so registering from a screen's `.task` would miss exactly the
    // case the feature exists for. Same reasoning as the Connect IQ line above.
    //
    // Once-gated: `FouleeApp` can be constructed more than once, and a second
    // observer would overwrite the handler slot the first one installed.
    private static let startMirrorObserverOnce: Void = {
        Task { @MainActor in await MirroredSessionStore.shared.observe() }
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
