import Foundation
import HealthKit

// HealthKit side of the source-agnostic active minutes (merge rules live in
// `ActiveMinutes`). Separate file to keep HealthKitClient+Live.swift within
// the file-length limit.

/// Per-day merged active minutes for the last `daysBack` days (today
/// included), oldest → newest, zero-filled. Enumerates the day range itself:
/// on a phone that never produced an `appleExerciseTime` sample the
/// statistics query returns nothing at all, and the merged series must still
/// cover every day so streaks and charts see real zeros.
func mergedDailyMinutes(
    store: HKHealthStore,
    minutesType: HKQuantityType,
    daysBack: Int
) async throws -> [DailyMinutes] {
    let calendar = Calendar.current
    let startOfToday = calendar.startOfDay(for: .now)
    let endOfToday = startOfToday.addingTimeInterval(24 * 60 * 60)
    guard let start = calendar.date(byAdding: .day, value: -(daysBack - 1), to: startOfToday) else {
        return []
    }
    async let appleTask = appleMinutesByBucket(
        store: store, type: minutesType, start: start, end: endOfToday, bucket: .day
    )
    async let workoutsTask = workoutIntervals(store: store, start: start, end: endOfToday)
    let appleByDay = try await appleTask
    let workoutsByDay = ActiveMinutes.workoutMinutesByDay(try await workoutsTask, calendar: calendar)
    var output: [DailyMinutes] = []
    var day = start
    while day < endOfToday {
        output.append(DailyMinutes(
            date: day,
            minutes: ActiveMinutes.merged(
                appleMinutes: appleByDay[day] ?? 0,
                workoutMinutes: workoutsByDay[day] ?? 0
            )
        ))
        day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(24 * 60 * 60)
    }
    return output
}

/// Today's workout minutes (all activity types, attributed by `startDate`)
/// for the `HealthMetrics.activeMinutes` and widget-snapshot merges.
func todayWorkoutMinutes(store: HKHealthStore) async throws -> Int {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: .now)
    let intervals = try await workoutIntervals(store: store, start: start, end: .now)
    return ActiveMinutes.workoutMinutesByDay(intervals, calendar: calendar)[start] ?? 0
}

/// Today's active minutes hour by hour (00:00 → now), oldest → newest and
/// zero-filled. Without it the stats screen showed a Garmin-only user a daily
/// bar at 25 min and an hourly curve flat at zero — the same number, two
/// different answers. The merge rule (and why it is decided on the day's
/// totals rather than hour by hour) lives in `ActiveMinutes`.
func mergedHourlyMinutesToday(
    store: HKHealthStore,
    minutesType: HKQuantityType
) async throws -> [MetricPoint] {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: .now)
    let end = Date.now
    async let appleTask = appleMinutesByBucket(
        store: store, type: minutesType, start: start, end: end, bucket: .hour
    )
    async let workoutsTask = workoutIntervals(store: store, start: start, end: end)
    let minutesByHour = ActiveMinutes.mergedHourlyMinutes(
        appleMinutesByHour: try await appleTask,
        workouts: try await workoutsTask,
        calendar: calendar
    )
    var output: [MetricPoint] = []
    var hour = start
    while hour < end {
        output.append(MetricPoint(date: hour, value: Double(minutesByHour[hour] ?? 0)))
        let next = calendar.date(byAdding: .hour, value: 1, to: hour) ?? hour.addingTimeInterval(3_600)
        guard next > hour else { break }
        hour = next
    }
    return output
}

/// Bucket granularity understood by `appleMinutesByBucket`. A closed two-case
/// enum rather than a `Calendar.Component`, so no caller can ask for a
/// granularity the query has no interval for and silently get days back.
private enum MinutesBucket {
    case day
    case hour

    /// Interval handed to `HKStatisticsCollectionQuery`.
    var interval: DateComponents {
        switch self {
        case .day: DateComponents(day: 1)
        case .hour: DateComponents(hour: 1)
        }
    }

    /// Calendar component the bucket keys are normalised to.
    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .hour: .hour
        }
    }
}

/// Raw `appleExerciseTime` minutes keyed by bucket start — the merge happens
/// in the callers. Empty when the range has no samples.
/// `HKStatisticsCollectionQuery` merges every source before summing (Apple
/// documented behaviour), so no manual per-source addition happens here.
private func appleMinutesByBucket(
    store: HKHealthStore,
    type: HKQuantityType,
    start: Date,
    end: Date,
    bucket: MinutesBucket
) async throws -> [Date: Int] {
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
    return try await withCheckedThrowingContinuation { continuation in
        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: bucket.interval
        )
        query.initialResultsHandler = { _, results, error in
            if isNoDataAvailable(error) {
                continuation.resume(returning: [:])
                return
            }
            if let error {
                continuation.resume(throwing: error)
                return
            }
            var minutesByBucket: [Date: Int] = [:]
            results?.enumerateStatistics(from: start, to: end) { statistic, _ in
                let minutes = statistic.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                // Normalize the bucket key through the calendar so it can't
                // drift from the keys the callers enumerate.
                let key = Calendar.current.dateInterval(of: bucket.component, for: statistic.startDate)?.start
                    ?? statistic.startDate
                minutesByBucket[key] = Int(minutes)
            }
            continuation.resume(returning: minutesByBucket)
        }
        store.execute(query)
    }
}

/// All `HKWorkout`s started in `start..<end`, any activity type, reduced to
/// the pure `WorkoutInterval` shape. Workouts are sparse — a plain
/// `HKSampleQuery` over the whole streak window is trivial.
private func workoutIntervals(
    store: HKHealthStore,
    start: Date,
    end: Date
) async throws -> [ActiveMinutes.WorkoutInterval] {
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
    return try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, error in
            if isNoDataAvailable(error) {
                continuation.resume(returning: [])
                return
            }
            if let error {
                continuation.resume(throwing: error)
                return
            }
            let workouts = (samples as? [HKWorkout]) ?? []
            continuation.resume(returning: workouts.map {
                ActiveMinutes.WorkoutInterval(start: $0.startDate, duration: $0.duration)
            })
        }
        store.execute(query)
    }
}
