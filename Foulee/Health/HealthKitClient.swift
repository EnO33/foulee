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

    /// Active minutes per calendar day for the last `daysBack` days,
    /// including today. Returns entries from oldest to newest with `0`
    /// minutes for days that had no exercise (so charts/streaks see gaps).
    var dailyMinutes: @Sendable (_ daysBack: Int) async throws -> [DailyMinutes]

    /// Walking workouts (HKWorkoutActivityType.walking) started since
    /// midnight today, newest first. Covers walks from Foulée, Forme
    /// and the Apple Watch — anything that's in HealthKit.
    var todayWorkouts: @Sendable () async throws -> [WorkoutSummary]
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
        saveWalkingWorkout: { _ in },
        dailyMinutes: { daysBack in previewDailyMinutes(daysBack: daysBack) },
        todayWorkouts: { previewTodayWorkouts() }
    )

    static let testValue = HealthKitClient(
        isAvailable: { false },
        requestAuthorization: { false },
        todayMetrics: { .zero },
        saveWalkingWorkout: { _ in },
        dailyMinutes: { _ in [] },
        todayWorkouts: { [] }
    )

    private static func previewTodayWorkouts() -> [WorkoutSummary] {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 5, second: 0, of: .now) ?? .now
        let ended = noon.addingTimeInterval(24 * 60)
        return [
            WorkoutSummary(
                id: UUID(),
                startedAt: noon,
                endedAt: ended,
                durationSeconds: 24 * 60,
                distanceKm: 1.8,
                activeCalories: 142,
                sourceName: "Apple Watch de Matthieu"
            )
        ]
    }

    /// Deterministic pseudo-history for `#Preview`s: 12-day current streak,
    /// 18-day historical record, mild noise around the 20 min goal.
    private static func previewDailyMinutes(daysBack: Int) -> [DailyMinutes] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let pattern = [24, 22, 21, 26, 23, 22, 25, 0, 28, 24, 23, 22, 24, 21, 0, 0, 25, 22, 24, 26, 23, 22, 21]
        return (0..<daysBack).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let minutes = pattern[offset % pattern.count]
            return DailyMinutes(date: date, minutes: minutes)
        }
    }
}

extension DependencyValues {
    var healthKit: HealthKitClient {
        get { self[HealthKitClient.self] }
        set { self[HealthKitClient.self] = newValue }
    }
}
