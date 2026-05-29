import Clocks
import Dependencies
import Foundation
import Testing
@testable import Foulee

@Suite("ActiveWalkStore")
struct ActiveWalkStoreTests {
    @Test("start transitions idle → active and assigns the start date")
    @MainActor
    func startTransitions() async {
        let frozen = Date(timeIntervalSince1970: 1_700_000_000)
        await withDependencies {
            $0.date = .constant(frozen)
            $0.pedometer = .testValue
            $0.healthKit = .testValue
            $0.continuousClock = TestClock()
        } operation: {
            let store = ActiveWalkStore()
            store.start()

            #expect(store.state == .active(WalkSession(startedAt: frozen)))
        }
    }

    @Test("start is a no-op when a session is already active")
    @MainActor
    func startIsIdempotent() async {
        let frozen = Date(timeIntervalSince1970: 1_700_000_000)
        await withDependencies {
            $0.date = .constant(frozen)
            $0.pedometer = .testValue
            $0.healthKit = .testValue
            $0.continuousClock = TestClock()
        } operation: {
            let store = ActiveWalkStore()
            store.start()
            let first = store.state
            store.start()

            #expect(store.state == first)
        }
    }

    @Test("stop finalises the session and saves it through HealthKit")
    @MainActor
    func stopSavesWorkout() async {
        let frozen = Date(timeIntervalSince1970: 1_700_000_000)
        let saved = LockedRef<WalkSession?>(nil)
        await withDependencies {
            $0.date = .constant(frozen)
            $0.pedometer = .testValue
            $0.continuousClock = TestClock()
            $0.healthKit = HealthKitClient(
                isAvailable: { true },
                requestAuthorization: { true },
                todayMetrics: { .zero },
                saveWalkingWorkout: { session in saved.set(session) },
                dailyMinutes: { _ in [] },
                recentWorkouts: { _ in [] },
                workoutDetail: { summary in
                    WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
                }
            )
        } operation: {
            let store = ActiveWalkStore()
            store.start()
            await store.stop()

            guard case .finished(let session) = store.state else {
                Issue.record("expected .finished state, got \(store.state)")
                return
            }
            #expect(session.endedAt == frozen)
            #expect(saved.value?.startedAt == frozen)
            #expect(store.lastError == nil)
        }
    }

    @Test("save failure surfaces lastError but still ends the session")
    @MainActor
    func saveFailureSurfaces() async {
        let frozen = Date(timeIntervalSince1970: 1_700_000_000)
        struct Boom: Error, LocalizedError {
            var errorDescription: String? { "Sauvegarde KO" }
        }
        await withDependencies {
            $0.date = .constant(frozen)
            $0.pedometer = .testValue
            $0.continuousClock = TestClock()
            $0.healthKit = HealthKitClient(
                isAvailable: { true },
                requestAuthorization: { true },
                todayMetrics: { .zero },
                saveWalkingWorkout: { _ in throw Boom() },
                dailyMinutes: { _ in [] },
                recentWorkouts: { _ in [] },
                workoutDetail: { summary in
                    WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
                }
            )
        } operation: {
            let store = ActiveWalkStore()
            store.start()
            await store.stop()

            #expect(store.lastError == "Sauvegarde KO")
            if case .finished = store.state {
                // expected
            } else {
                Issue.record("expected .finished state, got \(store.state)")
            }
        }
    }

    @Test("pause transitions active → paused, resume goes back to active")
    @MainActor
    func pauseResumeRoundTrip() async {
        let frozen = Date(timeIntervalSince1970: 1_700_000_000)
        await withDependencies {
            $0.date = .constant(frozen)
            $0.pedometer = .testValue
            $0.healthKit = .testValue
            $0.continuousClock = TestClock()
        } operation: {
            let store = ActiveWalkStore()
            store.start()
            await store.pause()
            #expect(store.state == .paused(WalkSession(startedAt: frozen)))

            store.resume()
            #expect(store.state == .active(WalkSession(startedAt: frozen)))
        }
    }

    @Test("pause is a no-op unless a session is active")
    @MainActor
    func pauseIgnoredWhenNotActive() async {
        await withDependencies {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.pedometer = .testValue
            $0.healthKit = .testValue
            $0.continuousClock = TestClock()
        } operation: {
            let store = ActiveWalkStore()
            await store.pause()
            #expect(store.state == .idle)

            // resume from idle is a no-op too
            store.resume()
            #expect(store.state == .idle)
        }
    }

    @Test("the route records the fixes the location client streams")
    @MainActor
    func routeRecordsFixes() async {
        let frozen = Date(timeIntervalSince1970: 1_700_000_000)
        let fixes = [
            Coordinate(latitude: 48.860, longitude: 2.330),
            Coordinate(latitude: 48.861, longitude: 2.331),
            Coordinate(latitude: 48.862, longitude: 2.332)
        ]
        await withDependencies {
            $0.date = .constant(frozen)
            $0.pedometer = .testValue
            $0.healthKit = .testValue
            $0.continuousClock = TestClock()
            $0.location = LocationClient(
                requestWhenInUse: { true },
                currentLocation: { nil },
                routeUpdates: {
                    AsyncStream { continuation in
                        for fix in fixes { continuation.yield(fix) }
                        continuation.finish()
                    }
                }
            )
        } operation: {
            let store = ActiveWalkStore()
            store.start()
            // Drain the immediate, finite route stream.
            var spins = 0
            while store.route.count < fixes.count, spins < 1_000 {
                await Task.yield()
                spins += 1
            }
            #expect(store.route == fixes)
        }
    }

    @Test("stop from a paused session still finalises and saves it")
    @MainActor
    func stopFromPausedSaves() async {
        let frozen = Date(timeIntervalSince1970: 1_700_000_000)
        let saved = LockedRef<WalkSession?>(nil)
        await withDependencies {
            $0.date = .constant(frozen)
            $0.pedometer = .testValue
            $0.continuousClock = TestClock()
            $0.healthKit = HealthKitClient(
                isAvailable: { true },
                requestAuthorization: { true },
                todayMetrics: { .zero },
                saveWalkingWorkout: { session in saved.set(session) },
                dailyMinutes: { _ in [] },
                recentWorkouts: { _ in [] },
                workoutDetail: { summary in
                    WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
                }
            )
        } operation: {
            let store = ActiveWalkStore()
            store.start()
            await store.pause()
            await store.stop()

            guard case .finished(let session) = store.state else {
                Issue.record("expected .finished state, got \(store.state)")
                return
            }
            #expect(session.endedAt == frozen)
            #expect(saved.value?.startedAt == frozen)
            #expect(store.lastError == nil)
        }
    }
}

/// Tiny actor wrapper for capturing values across `@Sendable` closures
/// in tests without bringing in heavyweight test doubles.
final class LockedRef<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ initial: Value) {
        self.stored = initial
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ new: Value) {
        lock.lock()
        defer { lock.unlock() }
        stored = new
    }
}
