import Dependencies
import Foundation
import Observation

/// Loads the Bilan (issues #344, #350): the recap of the last seven days and
/// of the last month, and their outings day by day.
///
/// One read of Santé covers both periods and the two before them: the series
/// reach back to the start of the month before last, whichever is earlier.
@MainActor
@Observable
final class RecapStore {
    private(set) var recaps: [RecapPeriod.Kind: Recap] = [:]
    /// Each period's days with their outings, in the order of its recap's days.
    private(set) var outings: [RecapPeriod.Kind: [OutingDay]] = [:]
    private(set) var isLoading = false
    private(set) var lastError: String?

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    @ObservationIgnored
    @Dependency(\.date) private var date

    func load(goalMinutes: Int, activeDays: Set<Weekday>) async {
        isLoading = true
        defer { isLoading = false }
        let now = date.now
        let periods = RecapPeriod.Kind.allCases.map { RecapPeriod.current($0, at: now) }
        let daysBack = Self.daysBack(covering: periods, from: now)
        do {
            let inputs = try await Self.readInputs(from: healthKit, daysBack: daysBack)
            recaps = Dictionary(uniqueKeysWithValues: periods.map {
                ($0.kind, Recap.make(period: $0, from: inputs, goalMinutes: goalMinutes, activeDays: activeDays))
            })
            outings = Dictionary(uniqueKeysWithValues: periods.map {
                ($0.kind, OutingDay.days(in: $0, from: inputs.workouts))
            })
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Everything a recap is made of, read from Santé in parallel.
    private static func readInputs(from healthKit: HealthKitClient, daysBack: Int) async throws -> Recap.Inputs {
        async let minutes = healthKit.dailyMinutes(daysBack)
        async let steps = healthKit.metricSeries(.steps, daysBack)
        async let distance = healthKit.metricSeries(.distance, daysBack)
        async let calories = healthKit.metricSeries(.calories, daysBack)
        async let workouts = healthKit.recentWorkouts(daysBack)
        return try await Recap.Inputs(
            minutes: minutes,
            steps: steps,
            distance: distance,
            calories: calories,
            workouts: workouts
        )
    }

    /// Days of history to read, today included, so the earliest period before
    /// those recapped is whole.
    static func daysBack(covering periods: [RecapPeriod], from now: Date, calendar: Calendar = .iso8601Monday) -> Int {
        let earliest = periods.map { $0.previous(calendar: calendar).start }.min() ?? now
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: calendar.startOfDay(for: now)).day ?? 0
        return days + 1
    }
}
