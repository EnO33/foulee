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
                dailyMinutes: { _ in [] }
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
                dailyMinutes: { _ in [] }
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
