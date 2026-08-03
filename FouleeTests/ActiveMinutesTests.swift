import Foundation
import Testing
@testable import Foulee

@Suite("ActiveMinutes")
struct ActiveMinutesTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = Date(timeIntervalSince1970: 1_716_768_000) // 2024-05-27, stable anchor

    private var startOfToday: Date { calendar.startOfDay(for: today) }

    @Test("Garmin-only day: workouts alone drive the minutes")
    func garminOnlyDay() {
        let workouts = [interval(hour: 12, minutes: 25)]
        let byDay = ActiveMinutes.workoutMinutesByDay(workouts, calendar: calendar)
        #expect(ActiveMinutes.merged(appleMinutes: 0, workoutMinutes: byDay[startOfToday] ?? 0) == 25)
    }

    @Test("Hybrid day: apple minutes already cover the workout — max, never addition")
    func hybridDay() {
        let byDay = ActiveMinutes.workoutMinutesByDay([interval(hour: 12, minutes: 20)], calendar: calendar)
        #expect(ActiveMinutes.merged(appleMinutes: 30, workoutMinutes: byDay[startOfToday] ?? 0) == 30)
    }

    @Test("Apple-only day unchanged (regression pin)")
    func appleOnlyDay() {
        let byDay = ActiveMinutes.workoutMinutesByDay([], calendar: calendar)
        #expect(ActiveMinutes.merged(appleMinutes: 30, workoutMinutes: byDay[startOfToday] ?? 0) == 30)
    }

    @Test("Empty day is 0")
    func emptyDay() {
        #expect(ActiveMinutes.workoutMinutesByDay([], calendar: calendar).isEmpty)
        #expect(ActiveMinutes.merged(appleMinutes: 0, workoutMinutes: 0) == 0)
    }

    @Test("Multiple workouts on one day sum their durations")
    func multiWorkoutDay() {
        let workouts = [interval(hour: 8, minutes: 10), interval(hour: 18, minutes: 15)]
        #expect(ActiveMinutes.workoutMinutesByDay(workouts, calendar: calendar)[startOfToday] == 25)
    }

    @Test("Midnight-crossing workout belongs to its start day")
    func midnightCrossing() {
        let start = startOfToday.addingTimeInterval(23 * 3_600 + 30 * 60) // 23:30
        let workouts = [ActiveMinutes.WorkoutInterval(start: start, duration: 3_600)]
        let byDay = ActiveMinutes.workoutMinutesByDay(workouts, calendar: calendar)
        #expect(byDay == [startOfToday: 60])
    }

    @Test("Daily total is capped at 1440")
    func cappedAtDayLength() {
        #expect(ActiveMinutes.merged(appleMinutes: 0, workoutMinutes: 2_000) == 1_440)
        #expect(ActiveMinutes.merged(appleMinutes: 2_000, workoutMinutes: 0) == 1_440)
    }

    @Test("Seconds are summed per day before truncating to minutes")
    func secondsSummedBeforeTruncation() {
        let workouts = [
            ActiveMinutes.WorkoutInterval(start: startOfToday.addingTimeInterval(8 * 3_600), duration: 90),
            ActiveMinutes.WorkoutInterval(start: startOfToday.addingTimeInterval(9 * 3_600), duration: 90)
        ]
        #expect(ActiveMinutes.workoutMinutesByDay(workouts, calendar: calendar)[startOfToday] == 3)
    }

    @Test("Negative inputs clamp to 0")
    func negativeInputs() {
        #expect(ActiveMinutes.merged(appleMinutes: -5, workoutMinutes: -3) == 0)
        let backwards = [ActiveMinutes.WorkoutInterval(start: startOfToday, duration: -600)]
        #expect(ActiveMinutes.workoutMinutesByDay(backwards, calendar: calendar)[startOfToday] == 0)
    }

    private func interval(hour: Int, minutes: Int) -> ActiveMinutes.WorkoutInterval {
        ActiveMinutes.WorkoutInterval(
            start: startOfToday.addingTimeInterval(TimeInterval(hour * 3_600)),
            duration: TimeInterval(minutes * 60)
        )
    }
}
