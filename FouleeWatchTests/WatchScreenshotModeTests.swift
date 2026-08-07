import Foundation
import HealthKit
import Testing
@testable import FouleeWatch

/// Records every call `WatchWorkoutStore` could make into HealthKit, and makes
/// none of them. A capture that touched Santé would show up here as a non-zero
/// counter rather than as a workout the owner discovers in Santé three weeks
/// later.
@MainActor
private final class TrapHealthKit {
    private(set) var availabilityChecks = 0
    private(set) var authorizationRequests = 0
    private(set) var sessionStarts = 0

    var calls: Int { availabilityChecks + authorizationRequests + sessionStarts }

    func makeStore() -> WatchWorkoutStore {
        WatchWorkoutStore(healthKit: WatchWorkoutHealthKit(
            isAvailable: {
                self.availabilityChecks += 1
                return true
            },
            requestAuthorization: { _, _ in
                self.authorizationRequests += 1
            },
            startSession: { _, _ in
                self.sessionStarts += 1
                return WatchWorkoutSessionHandle(
                    end: {},
                    endCollection: { _ in },
                    finishWorkout: {},
                    collectionEndDate: { nil }
                )
            }
        ))
    }
}

/// The constraints of the watch capture mode (issue #239), asserted rather than
/// promised: never active in production, showing the *phone's* numbers, and
/// writing nothing to Santé.
///
/// One thing here has no runtime assertion, by nature rather than by omission.
/// "A Release build contains none of this" is enforced by the `#if DEBUG`
/// wrapping every file under `FouleeWatch/Screenshots/` and every guard that
/// names `WatchScreenshotMode` — this suite itself only compiles because it
/// runs against a Debug build. And the mode is deliberately never *activated*
/// from a test: flipping a process-global on would make the assertions below
/// depend on test ordering, which is the very thing they exist to rule out. So
/// each seeded path is driven through the function the guard calls, not through
/// the guard.
@MainActor
@Suite("Watch screenshot mode")
struct WatchScreenshotModeTests {
    // MARK: - Never active in production

    /// The one that matters: this process is a normal launch of the watch app
    /// (the test host), and it must not be in capture mode.
    @Test("A normal launch does not activate the capture mode")
    func normalLaunchDoesNotActivate() {
        #expect(WatchScreenshotMode.isRequested(arguments: ProcessInfo.processInfo.arguments) == false)
        #expect(WatchScreenshotMode.isActive == false)
    }

    @Test("Only the explicit launch argument requests the capture mode")
    func onlyTheExplicitArgumentActivates() {
        #expect(WatchScreenshotMode.isRequested(arguments: []) == false)
        #expect(WatchScreenshotMode.isRequested(arguments: ["/tmp/FouleeWatch.app/FouleeWatch"]) == false)
        #expect(WatchScreenshotMode.isRequested(arguments: ["-FouleeScreenshot"]) == false)
        #expect(WatchScreenshotMode.isRequested(arguments: ["screenshots"]) == false)
        #expect(WatchScreenshotMode.isRequested(arguments: [WatchScreenshotMode.launchArgument]))
    }

    /// A UI test target is a separate process and cannot import app code, so
    /// `FouleeWatchScreenshots` spells the argument as a literal. Pinning the
    /// exact string here is what keeps a rename from silently turning every
    /// watch capture into a photograph of an empty simulator's zeros.
    @Test("The launch argument keeps the spelling the capture target passes")
    func launchArgumentSpelling() {
        #expect(WatchScreenshotMode.launchArgument == "-FouleeScreenshotMode")
    }

    // MARK: - The same day as the phone

    /// The seeded home is the phone's seed, field by field — this is what stops
    /// a 34-day streak on the phone board and another number on the wrist board
    /// from reaching the same App Store listing.
    @Test("The seeded home serves the shared seed, not the watch's own numbers")
    func seededHomeMatchesTheSharedSeed() {
        let store = WatchTodayStore()
        store.applyScreenshotSeed()

        #expect(store.streak == ScreenshotSeed.currentStreak)
        #expect(store.steps == ScreenshotSeed.todaySteps)
        #expect(store.minutes == ScreenshotSeed.todayMinutes)
        #expect(store.distanceKm == ScreenshotSeed.todayDistanceKm)
        #expect(store.calories == ScreenshotSeed.todayCalories)
        #expect(store.stepsGoal == ScreenshotSeed.stepsGoal)
        #expect(store.minutesGoal == ScreenshotSeed.minutesGoal)
        #expect(store.waterML == ScreenshotSeed.waterML)
        #expect(store.hydrationGoalML == ScreenshotSeed.hydrationGoalML)
        #expect(store.hydrationGlassML == ScreenshotSeed.hydrationGlassML)
    }

    /// The three screens the capture photographs must all be *reachable*: the
    /// hydration card only renders when hydration is on, the home only drops
    /// the « Ouvre Foulée sur ton iPhone » hint once a payload has been seen,
    /// and neither the denial nor the error banner may be up.
    @Test("The seeded home renders the screens the capture needs")
    func seededHomeIsPresentable() {
        let store = WatchTodayStore()
        store.applyScreenshotSeed()

        #expect(store.hydrationEnabled)
        #expect(store.hasPhoneSync)
        #expect(store.isLoading == false)
        #expect(store.waterDenied == false)
        #expect(store.hydrationError == nil)
    }

    /// Deterministic by construction: the seeded values are constants, so the
    /// same store seeded twice — and any two capture runs — carry the same
    /// numbers whatever day it is.
    @Test("Seeding twice gives the same numbers")
    func seedingIsDeterministic() {
        let first = WatchTodayStore()
        first.applyScreenshotSeed()
        let second = WatchTodayStore()
        second.applyScreenshotSeed()

        #expect(first.steps == second.steps)
        #expect(first.streak == second.streak)
        #expect(first.distanceKm == second.distanceKm)
        #expect(first.waterML == second.waterML)
    }

    // MARK: - Zero HealthKit writes

    /// The invariant issue #239 states — « Aucune écriture HealthKit depuis ce
    /// chemin » — for the one screen that could plausibly write one: the
    /// session. The store is built on a HealthKit double that counts every
    /// call, the seeded session is started, and then stopped for good measure.
    ///
    /// Nothing is counted, which is stronger than "saveWorkout is a no-op":
    /// there is no session, no builder and no handle, so there is nothing for
    /// `stop()` to finish even if it tried.
    @Test("The seeded session opens no workout and stopping it saves nothing")
    func seededSessionNeverReachesHealthKit() async {
        let trap = TrapHealthKit()
        let store = trap.makeStore()

        store.startScreenshotSession()
        #expect(store.state == .active(ScreenshotSeed.watchSessionMetrics))
        #expect(trap.calls == 0)

        await store.stop()
        // Still active, still untouched: `stop()` needs a session handle, and
        // the seeded path never made one.
        #expect(store.state == .active(ScreenshotSeed.watchSessionMetrics))
        #expect(trap.calls == 0)
    }

    /// The seeded session is the phone's session — same elapsed time, same
    /// steps, same distance — plus the two counters only the wrist measures.
    @Test("The seeded session is the phone's session")
    func seededSessionMatchesTheSharedSeed() {
        let metrics = ScreenshotSeed.watchSessionMetrics
        #expect(metrics.elapsed == ScreenshotSeed.sessionElapsed)
        #expect(metrics.steps == ScreenshotSeed.sessionSteps)
        #expect(metrics.distanceMeters == ScreenshotSeed.sessionDistanceMeters)
        #expect(metrics.activeCalories == ScreenshotSeed.sessionCalories)
        #expect(metrics.heartRate == ScreenshotSeed.sessionHeartRate)
    }

    /// Checked where it is decidable, the way the phone suite does it: writing
    /// a sample takes an `HKHealthStore`, so no file under
    /// `FouleeWatch/Screenshots/` may so much as name one — nor reach any of
    /// the stores a capture run must leave alone.
    ///
    /// Comments are stripped before matching, so the prose in those files stays
    /// free to name what it forbids — as this very comment does.
    @Test("No capture-mode source can reach a store")
    func captureSourcesCannotReachAStore() throws {
        let forbidden = [
            "import HealthKit", "HKHealthStore", "HKObserverQuery", "HKQuantity",
            "UserDefaults", "WatchSyncStore", "WidgetCenter"
        ]
        let files = try FileManager.default.contentsOfDirectory(
            at: Self.captureSourceDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        // A scan that found nothing would pass every assertion below.
        #expect(files.count >= 2)
        for file in files {
            let code = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            for symbol in forbidden {
                // Through a `Bool` rather than inline, so a failure reports the
                // file and the symbol instead of dumping the whole source.
                let names = code.contains(symbol)
                #expect(names == false, "\(file.lastPathComponent) names \(symbol)")
            }
        }
    }

    /// `FouleeWatch/Screenshots/`, resolved from this file rather than from a
    /// bundle: the sources are not shipped into the test bundle, and the only
    /// path that survives is the one the compiler recorded.
    private static let captureSourceDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()   // FouleeWatchTests/
        .deletingLastPathComponent()   // repository root
        .appending(path: "FouleeWatch/Screenshots")
}
