@preconcurrency import ActivityKit
@preconcurrency import BackgroundTasks
import Dependencies
import FouleeKit
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
        _ = Self.recordLaunchOnce
    }

    var body: some Scene {
        WindowGroup {
            RootView(defaults: Self.preferencesDefaults)
                .onOpenURL(perform: Self.handleGarminDeviceSelection)
        }
    }

    /// Garmin Connect's answer to « Choisir ma montre »: on the scene, since
    /// iOS may relaunch the app to deliver it, onboarding or not.
    private static func handleGarminDeviceSelection(_ url: URL) {
        guard GarminConnectIQConfiguration.isDeviceSelectionResponse(url) else { return }
        @Dependency(\.garminConnectIQ) var garminConnectIQ
        _ = garminConnectIQ.handleDeviceSelection(url)
    }

    /// Where the app reads the user's preferences from — always `.standard`,
    /// except during a screenshot capture, which gets a throwaway suite so it
    /// can seed goals and a theme without touching the real install.
    static var preferencesDefaults: UserDefaults {
        #if DEBUG
        ScreenshotMode.preferencesDefaults ?? .standard
        #else
        .standard
        #endif
    }

    private static let recordLaunchOnce: Void = ReviewPromptStore.shared.recordLaunch()

    private static let registerAppRefreshOnce: Void = {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            FouleeLog.background.notice("rafraîchissement : réveil")
            scheduleAppRefresh() // chain the next wake
            let start = Date.now
            let work = Task {
                await refreshWidgetSnapshotFromHealth()
                WidgetCenter.shared.reloadAllTimelines()
            }
            // Set the handler before awaiting the result, and complete the
            // task on every path — including expiration — so iOS doesn't
            // penalise future background grants for an un-completed task.
            task.expirationHandler = {
                FouleeLog.background.error("rafraîchissement : temps écoulé, tâche annulée")
                work.cancel()
            }
            Task {
                _ = await work.value
                let success = !work.isCancelled
                let outcome = success ? "succès" : "échec"
                let seconds = Date.now.timeIntervalSince(start)
                FouleeLog.background.notice(
                    "rafraîchissement : \(outcome, privacy: .public) en \(seconds, format: .fixed(precision: 1), privacy: .public) s"
                )
                task.setTaskCompleted(success: success)
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
            // A mirror wake is a launch too (#275): the activity it starts is
            // not an orphan.
            let startedHere = MirroredLiveActivity.startedHere.withLock { $0 }
            for activity in Activity<WalkActivityAttributes>.activities where !startedHere.contains(activity.id) {
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
        // Opened before the observers can fire, so the first outing they
        // announce is one that ended after this version arrived (#529).
        SessionNotifier.prepare()
        Task { await healthKit.enableBackgroundDelivery() }
    }()

    // Connect IQ has to be initialized at *process* start, not when a screen
    // appears: the point of the BLE state-restoration identifier is that iOS
    // relaunches the app in the background when the paired Garmin watch has
    // data, and on that path no UI is ever mounted. Re-registering the known
    // devices immediately is what makes the wake useful.
    //
    // Each decoded snapshot then goes to `GarminSnapshotIngestion`, which owns
    // the day-stamped overlay and the merge (#189). None of the day's counters
    // is ever written to HealthKit: Garmin Connect syncs the same day later,
    // and a sample written here would double-count it forever. The one write
    // is a glass noted at the watch (ADR 0009, D8), which only the phone can
    // write and Garmin Connect never syncs (`GarminWaterIngestion`).
    private static let startGarminConnectIQOnce: Void = {
        @Dependency(\.garminConnectIQ) var garminConnectIQ
        @Dependency(\.healthKit) var healthKit
        garminConnectIQ.initialize()
        garminConnectIQ.startReceiving()
        // Everything the two tasks need is read here, before either starts:
        // a property wrapper sent to one task can't be touched again by the
        // next, the streams and the client can.
        let snapshots = garminConnectIQ.snapshots()
        let waterArrivals = garminConnectIQ.waterArrivals()
        let healthKitClient = healthKit
        Task { await GarminSnapshotIngestion.run(snapshots) }
        Task { await GarminWaterIngestion.run(waterArrivals, healthKit: healthKitClient) }
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
        Task { @MainActor in
            await MirroredSessionStore.shared.observe { store in
                await MirroredLiveActivity.shared.reflect(store)
            }
        }
        Task { @MainActor in
            await MirroredSessionStore.shared.observeGarmin { store in
                await MirroredLiveActivity.shared.reflect(store)
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
        do {
            try BGTaskScheduler.shared.submit(request)
            FouleeLog.background.info("rafraîchissement : prochain réveil demandé")
        } catch {
            // Refused on the simulator, or when « Actualisation en arrière-plan »
            // is off: no refresh task will ever run, and this is the only trace.
            FouleeLog.background.error(
                "rafraîchissement : demande refusée : \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
