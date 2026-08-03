import Foundation

/// Source-agnostic active-minutes math (issue #181).
///
/// `appleExerciseTime` is read-only and Apple-generated: without an Apple
/// Watch iOS never produces a single sample, so a Garmin-only user (whose
/// Garmin Connect writes its sessions into Health as `HKWorkout`s) would see
/// zero minutes, a dead hero ring and a streak that can never start. Each
/// day's active minutes are therefore derived from both signals:
///
/// - Workout minutes = sum of the durations of ALL workout activity types
///   that day. This matches `appleExerciseTime` semantics, which credits any
///   exercise — a Garmin user's yoga session is active minutes, exactly like
///   Apple's ring. Never restrict to `.walking`.
/// - A workout belongs to the calendar day of its `startDate` (simple and
///   deterministic — a walk crossing midnight credits the day it began).
/// - Day value = `max(appleMinutes, workoutMinutes)`, never a sum: a hybrid
///   Apple Watch + Garmin user's workout is already counted inside
///   `appleExerciseTime`, so adding the two would double-count.
/// - Capped at 1440, the number of minutes in a day.
///
/// Pure Foundation so it compiles into both the app and the widget
/// extension (see Project.swift).
enum ActiveMinutes {
    /// Minutes in a civil day — upper bound for any daily total.
    static let dailyCap = 1_440

    /// The two facts about a workout the merge needs, decoupled from
    /// `HKWorkout` so the math stays pure and testable.
    struct WorkoutInterval: Equatable, Sendable {
        var start: Date
        var duration: TimeInterval
    }

    /// One day's merged value: `max(apple, workouts)` clamped to
    /// `0...dailyCap`.
    static func merged(appleMinutes: Int, workoutMinutes: Int) -> Int {
        min(max(appleMinutes, workoutMinutes, 0), dailyCap)
    }

    /// Whole workout minutes per day (keyed by the day's start), every
    /// activity type included, each workout attributed to its `start`'s day.
    /// Seconds are summed per day before truncating so short sessions don't
    /// each lose up to a minute.
    static func workoutMinutesByDay(
        _ workouts: [WorkoutInterval],
        calendar: Calendar = .current
    ) -> [Date: Int] {
        var secondsByDay: [Date: TimeInterval] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.start)
            secondsByDay[day, default: 0] += max(workout.duration, 0)
        }
        return secondsByDay.mapValues { Int($0 / 60) }
    }
}
