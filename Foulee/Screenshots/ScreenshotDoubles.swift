#if DEBUG
import FouleeKit
import Foundation

/// The dependency doubles the capture mode installs. Same struct-of-closures
/// the app already uses for `previewValue` / `testValue` — no new seam, no
/// production branch: `ScreenshotMode` swaps the values, the app code is
/// untouched.
///
/// **Read-only by construction.** Every closure that would write something —
/// `saveWorkout`, `logWater`, `deleteWater`, `enableBackgroundDelivery`, the Connect IQ
/// initializer, every notification scheduler — is `{}`. Capturing a session
/// therefore records no `HKWorkout`, tapping « J'ai bu » stores no
/// `dietaryWater` sample, and no observer is registered against the real
/// HealthKit store. Nothing in this file imports HealthKit at all.
nonisolated enum ScreenshotDoubles {
    static let healthKit = HealthKitClient(
        requestAuthorization: { true },
        todayMetrics: { ScreenshotSeed.todayMetrics },
        // Deliberately a no-op: the session capture runs `ActiveWalkStore.stop()`,
        // which is the app's only workout write. Here it persists nothing.
        saveWorkout: { _ in },
        dailyMinutes: { ScreenshotSeed.dailyMinutes(daysBack: $0) },
        recentWorkouts: { ScreenshotSeed.recentWorkouts(daysBack: $0) },
        workoutDetail: { ScreenshotSeed.workoutDetail($0) },
        metricSeries: { ScreenshotSeed.metricSeries($0, daysBack: $1) },
        hourlyToday: { ScreenshotSeed.hourlyToday($0) },
        // No change streams: a refresh mid-capture could only redraw the same
        // numbers, and an open stream keeps a task alive for the whole run.
        observeChanges: { AsyncStream { $0.finish() } },
        observeWaterChanges: { AsyncStream { $0.finish() } },
        // The other write. Tapping « J'ai bu » on camera logs nothing; the card
        // keeps showing the seeded intake, which is what makes the capture
        // reproducible anyway.
        logWater: { _ in UUID() },
        deleteWater: { _ in },
        todayWaterML: { ScreenshotSeed.waterML },
        waterWriteDenied: { false },
        waterToday: { ScreenshotSeed.waterToday },
        waterSeries: { ScreenshotSeed.waterSeries(daysBack: $0) },
        garminStatus: { ScreenshotSeed.garminStatus },
        enableBackgroundDelivery: {}
    )

    static let weather = WeatherClient(
        forecast: { _, _ in ScreenshotSeed.weather }
    )

    static let location = LocationClient(
        requestWhenInUse: { true },
        currentLocation: { ScreenshotSeed.coordinate },
        // The fixed route, emitted once and then held open: the map sheet draws
        // the same polyline every run, and re-emitting would add nothing.
        routeUpdates: {
            AsyncStream { continuation in
                ScreenshotSeed.route.forEach { continuation.yield($0) }
            }
        }
    )

    static let notifications = NotificationsClient(
        requestAuthorization: { true },
        // "authorized" so the hero bell renders enabled rather than the
        // "refusées dans Réglages" warning state.
        authorizationStatus: { .authorized },
        replaceWalkReminders: { _ in },
        scheduleSnooze: { _ in },
        configureHydrationCategory: { _ in },
        replaceHydrationReminders: { _ in },
        scheduleHydrationSnooze: { _ in }
    )

    /// `outing`: the Garmin states one outing in progress, once — the Garmin
    /// mirror board. Otherwise it states nothing.
    static func garminConnectIQ(outing: Bool) -> GarminConnectIQClient {
        GarminConnectIQClient(
            // No SDK initialization, no BLE, no Garmin Connect round-trip.
            initialize: {},
            presentDeviceSelection: {},
            handleDeviceSelection: { _ in ScreenshotSeed.garminDevices },
            knownDevices: { ScreenshotSeed.garminDevices },
            startReceiving: {},
            snapshots: { AsyncStream { $0.finish() } },
            sessionStates: { finite(outing ? [ScreenshotSeed.wristFigures(from: .garmin)] : []) },
            waterArrivals: { AsyncStream { $0.finish() } },
            requestStop: {},
            // nil, not a contribution: the seeded counters are already the whole
            // day's story, and an overlay on top of them would lift the hero card
            // above the numbers every other screen shows.
            todayOverlay: { _ in nil }
        )
    }

    /// `outing`: an Apple Watch is recording when the app opens, and says so
    /// once — the Apple Watch mirror board. Otherwise no wrist ever mirrors.
    /// Nothing is sent and nothing is woken either way: there is no watch.
    static func mirroredWorkout(outing: Bool) -> MirroredWorkoutClient {
        let figures = ScreenshotSeed.wristFigures(from: .appleWatch)
        let events: [MirroredSessionEvent] = outing ? [
            .started(MirroredSession(startedAt: figures.outingStartedAt, activity: figures.activity)),
            .snapshot(figures)
        ] : []
        return MirroredWorkoutClient(
            events: { finite(events) },
            send: { _ in },
            startWatchSession: { _ in },
            isWatchAppInstalled: { false }
        )
    }

    /// Every element, then the end.
    private static func finite<Element: Sendable>(_ elements: [Element]) -> AsyncStream<Element> {
        AsyncStream { continuation in
            elements.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    /// Drives the session-in-progress capture. Emits the same sample forever —
    /// the store drops samples that arrive before it has set its state, so a
    /// single yield would race — after moving `ScreenshotClock` to the fixed
    /// session offset. Both halves are idempotent, so the screen settles on
    /// exactly one set of numbers and stays there.
    static let pedometer = Pedometer(
        startUpdates: { _ in
            AsyncStream { continuation in
                Task {
                    while !Task.isCancelled {
                        ScreenshotClock.shared.advance(toOffset: ScreenshotSeed.sessionElapsed)
                        continuation.yield(
                            PedometerSample(
                                steps: ScreenshotSeed.sessionSteps,
                                distanceMeters: ScreenshotSeed.sessionDistanceMeters
                            )
                        )
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                    continuation.finish()
                }
            }
        },
        stop: {},
        // Capture mode records nothing, so nothing ever asks — and a number
        // here would be a step count no seeded screen shows.
        steps: { _, _ in nil }
    )

    static let altimeter = Altimeter(
        startUpdates: {
            AsyncStream { continuation in
                Task {
                    while !Task.isCancelled {
                        continuation.yield(Elevation(ascent: ScreenshotSeed.sessionElevationMeters, descent: 0))
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                    continuation.finish()
                }
            }
        },
        stop: {}
    )
}
#endif
