import Dependencies
import Foundation

/// Thin, testable façade over HealthKit. All entry points are `async` and
/// `throws`; callers propagate or trap once at the highest sensible boundary
/// (`TodayStore.refresh()`).
///
/// The struct-of-closures shape (Point-Free convention) lets previews and
/// tests swap in deterministic stubs without subclassing or mocking.
struct HealthKitClient: Sendable {
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

    /// Walking workouts (HKWorkoutActivityType.walking) started in the
    /// last `daysBack` days (today included), newest first. Covers walks
    /// from Foulée, Forme and the Apple Watch — anything in HealthKit.
    /// Pass `1` for today only.
    var recentWorkouts: @Sendable (_ daysBack: Int) async throws -> [WorkoutSummary]

    /// Drill-down for a single workout — heart-rate samples + steps
    /// scoped on the workout's exact window. Re-fetches the underlying
    /// `HKWorkout` by UUID so the queries can use
    /// `predicateForObjects(from: workout)` and avoid catching samples
    /// from before or after the session.
    var workoutDetail: @Sendable (_ summary: WorkoutSummary) async throws -> WorkoutDetail

    /// Daily totals of `metric` for the last `daysBack` days (today
    /// included), oldest → newest and zero-filled. Values are already in the
    /// metric's display unit (steps, minutes, km, kcal). Drives the per-metric
    /// stats charts for the Week/Month ranges. Defaults to empty so existing
    /// test stubs that don't care about it compile unchanged.
    var metricSeries: @Sendable (_ metric: WalkMetric, _ daysBack: Int) async throws -> [MetricPoint]
        = { _, _ in [] }

    /// Hourly totals of `metric` for today (00:00 → now), one point per hour.
    /// Drives the "Aujourd'hui" curve.
    var hourlyToday: @Sendable (_ metric: WalkMetric) async throws -> [MetricPoint]
        = { _ in [] }

    /// Emits whenever the user's step/distance/exercise/energy data changes, so
    /// the Today dashboard can refresh live as steps accumulate — no need to
    /// reopen the app or start a walk. Defaults to a stream that never fires.
    var observeChanges: @Sendable () -> AsyncStream<Void>
        = { AsyncStream { $0.finish() } }

    /// Emits whenever `dietaryWater` changes — including water that synced in
    /// from the paired watch — so the hydration card can refresh live instead
    /// of showing a stale total. Defaults to a stream that never fires.
    var observeWaterChanges: @Sendable () -> AsyncStream<Void>
        = { AsyncStream { $0.finish() } }

    /// Log one drink to Apple Health as a `dietaryWater` sample of
    /// `milliliters`. Defaulted to a no-op so existing test stubs compile.
    var logWater: @Sendable (_ milliliters: Int) async throws -> Void
        = { _ in }

    /// Total `dietaryWater` logged today, in millilitres. Defaulted to 0.
    var todayWaterML: @Sendable () async throws -> Int
        = { 0 }

    /// Whether the user explicitly denied *writing* `dietaryWater`. Read
    /// denial is invisible by design (queries just return zeros), but write
    /// denial is detectable — check it before logging a glass so the failure
    /// can be explained instead of swallowed. Defaulted to `false`.
    var waterWriteDenied: @Sendable () async -> Bool
        = { false }

    /// Soft detection of the watch behind the user's Health data (issue #185):
    /// is a Garmin source writing into Santé, is there any Apple Watch data,
    /// and when did Garmin last push something today. Never throws — a missing
    /// verdict just means "nothing detected", which keeps every adapted hint
    /// off. Defaulted so stubs that don't care compile unchanged.
    var garminStatus: @Sendable () async -> GarminStatus
        = { GarminStatus() }

    /// Ask iOS to wake the app (hourly, the finest steps cadence allowed) when
    /// new Health samples land, so the widget snapshot stays fresh without the
    /// app being opened. Defaulted to a no-op.
    var enableBackgroundDelivery: @Sendable () async -> Void
        = {}
}

extension HealthKitClient: DependencyKey {
    /// Stub used in `#Preview` and in tests unless explicitly overridden.
    /// `liveValue` is supplied in `HealthKitClient+Live.swift` so this file
    /// stays HealthKit-free and previewable on any platform.
    static let previewValue = HealthKitClient(
        requestAuthorization: { true },
        todayMetrics: {
            HealthMetrics(steps: 4_218, distanceKm: 1.8, activeMinutes: 24, activeCalories: 142)
        },
        saveWalkingWorkout: { _ in },
        dailyMinutes: { daysBack in previewDailyMinutes(daysBack: daysBack) },
        recentWorkouts: { daysBack in previewRecentWorkouts(daysBack: daysBack) },
        workoutDetail: { summary in previewWorkoutDetail(summary: summary) },
        metricSeries: { metric, daysBack in previewMetricSeries(metric: metric, daysBack: daysBack) },
        hourlyToday: { metric in previewHourlyToday(metric: metric) },
        todayWaterML: { 1_000 }
    )

    static let testValue = HealthKitClient(
        requestAuthorization: { false },
        todayMetrics: { .zero },
        saveWalkingWorkout: { _ in },
        dailyMinutes: { _ in [] },
        recentWorkouts: { _ in [] },
        workoutDetail: { summary in
            WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
        },
        metricSeries: { _, _ in [] },
        hourlyToday: { _ in [] }
    )

    /// Mock detail used in `#Preview`: linear HR ramp from ~95 bpm to
    /// ~115 bpm over the workout, 5 samples per minute, plus a
    /// proportional step count (≈115 steps/min for casual walking).
    private static func previewWorkoutDetail(summary: WorkoutSummary) -> WorkoutDetail {
        let totalSeconds = Int(summary.durationSeconds)
        let sampleStride = 12
        let samples = stride(from: 0, through: totalSeconds, by: sampleStride).map { offset in
            let date = summary.startedAt.addingTimeInterval(TimeInterval(offset))
            let progress = Double(offset) / Double(max(totalSeconds, 1))
            let bpm = Int(95 + progress * 20 + sin(progress * 6) * 4)
            return HeartRateSample(id: UUID(), date: date, bpm: bpm)
        }
        let estimatedSteps = Int(summary.durationSeconds / 60 * 115)
        return WorkoutDetail(
            summary: summary,
            heartRateSamples: samples,
            stepsCount: estimatedSteps
        )
    }

    /// Mock history that covers a full week — today + 2 random "miss"
    /// days in the past so the sheet can showcase both populated days
    /// and the empty-day placeholder.
    private static func previewRecentWorkouts(daysBack: Int) -> [WorkoutSummary] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let skipOffsets: Set<Int> = [3, 5]
        return (0..<daysBack).flatMap { offset -> [WorkoutSummary] in
            guard !skipOffsets.contains(offset) else { return [] }
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let start = calendar.date(bySettingHour: 12, minute: 5, second: 0, of: day) ?? day
            let durationMinutes = 22 + offset % 4
            let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
            return [
                WorkoutSummary(
                    id: UUID(),
                    startedAt: start,
                    endedAt: end,
                    durationSeconds: TimeInterval(durationMinutes * 60),
                    distanceKm: 1.6 + Double(offset % 3) * 0.2,
                    activeCalories: 120 + offset * 6,
                    sourceName: offset == 0 ? "Foulée" : "Apple Watch de Matthieu"
                )
            ]
        }
    }

    /// Deterministic per-metric daily history for `#Preview`s — mild variation
    /// per day, no randomness.
    private static func previewMetricSeries(metric: WalkMetric, daysBack: Int) -> [MetricPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<daysBack).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let wave = Double((offset * 7) % 5) // 0…4
            let value: Double = switch metric {
            case .steps: 4_500 + wave * 380
            case .minutes: 20 + wave * 2
            case .distance: 3.2 + wave * 0.3
            case .calories: 120 + wave * 18
            }
            return MetricPoint(date: date, value: value)
        }
    }

    /// Deterministic hourly curve for `#Preview`s — activity concentrated
    /// around the midday walk, from 00:00 up to the current hour.
    private static func previewHourlyToday(metric: WalkMetric) -> [MetricPoint] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let currentHour = calendar.component(.hour, from: .now)
        let peak: Double = switch metric {
        case .steps: 1_800
        case .minutes: 8
        case .distance: 1.4
        case .calories: 55
        }
        return (0...max(currentHour, 0)).map { hour in
            let date = calendar.date(byAdding: .hour, value: hour, to: start) ?? start
            let closeness = max(0, 1 - abs(Double(hour) - 12) / 6) // triangular peak at noon
            return MetricPoint(date: date, value: (peak * closeness).rounded())
        }
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
