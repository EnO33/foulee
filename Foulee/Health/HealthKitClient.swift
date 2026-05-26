import Dependencies
import Foundation

/// Thin, testable façade over HealthKit. All entry points are `async` and
/// `throws`; callers propagate or trap once at the highest sensible boundary
/// (`TodayStore.refresh()`).
///
/// The struct-of-closures shape (Point-Free convention) lets previews and
/// tests swap in deterministic stubs without subclassing or mocking.
struct HealthKitClient: Sendable {
    /// True iff HealthKit is available on this device (false on iPad without
    /// the framework, on macOS, …). Always check before any other call.
    var isAvailable: @Sendable () -> Bool

    /// Prompts the user with the system HealthKit sheet on first call.
    /// Returns `true` once permissions have been requested (even if denied —
    /// the system never tells us per-type denial, by design).
    var requestAuthorization: @Sendable () async throws -> Bool

    /// Sum of pas + distance + minutes + active kcal between midnight today
    /// and now, in the user's current calendar.
    var todayMetrics: @Sendable () async throws -> HealthMetrics

    /// Persists a finished walk as an `HKWorkout` (activity type: walking,
    /// location: outdoor). Idempotent at the call site — duplicate saves on
    /// the same session are caller-controlled, not deduplicated here.
    var saveWalkingWorkout: @Sendable (_ session: WalkSession) async throws -> Void
}

extension HealthKitClient: DependencyKey {
    /// Stub used in `#Preview` and in tests unless explicitly overridden.
    /// `liveValue` is supplied in `HealthKitClient+Live.swift` so this file
    /// stays HealthKit-free and previewable on any platform.
    static let previewValue = HealthKitClient(
        isAvailable: { true },
        requestAuthorization: { true },
        todayMetrics: {
            HealthMetrics(steps: 4_218, distanceKm: 1.8, activeMinutes: 24, activeCalories: 142)
        },
        saveWalkingWorkout: { _ in }
    )

    static let testValue = HealthKitClient(
        isAvailable: { false },
        requestAuthorization: { false },
        todayMetrics: { .zero },
        saveWalkingWorkout: { _ in }
    )
}

extension DependencyValues {
    var healthKit: HealthKitClient {
        get { self[HealthKitClient.self] }
        set { self[HealthKitClient.self] = newValue }
    }
}
