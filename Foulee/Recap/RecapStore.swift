import Dependencies
import Foundation
import Observation

/// Loads the week and month recaps (issue #344).
///
/// One read of Santé covers both periods and the two before them: the series
/// reach back to the start of the month before last, whichever is earlier.
@MainActor
@Observable
final class RecapStore {
    private(set) var recaps: [RecapPeriod.Kind: Recap] = [:]
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
        let periods = RecapPeriod.Kind.allCases.map { RecapPeriod.lastCompleted($0, before: now) }
        let daysBack = Self.daysBack(covering: periods, from: now)
        do {
            async let minutes = healthKit.dailyMinutes(daysBack)
            async let steps = healthKit.metricSeries(.steps, daysBack)
            async let distance = healthKit.metricSeries(.distance, daysBack)
            async let calories = healthKit.metricSeries(.calories, daysBack)
            async let workouts = healthKit.recentWorkouts(daysBack)
            let inputs = try await Recap.Inputs(
                minutes: minutes,
                steps: steps,
                distance: distance,
                calories: calories,
                workouts: workouts
            )
            recaps = Dictionary(uniqueKeysWithValues: periods.map {
                ($0.kind, Recap.make(period: $0, from: inputs, goalMinutes: goalMinutes, activeDays: activeDays))
            })
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Days of history to read, today included, so the earliest period before
    /// those recapped is whole.
    static func daysBack(covering periods: [RecapPeriod], from now: Date, calendar: Calendar = .iso8601Monday) -> Int {
        let earliest = periods.map { $0.previous(calendar: calendar).start }.min() ?? now
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: calendar.startOfDay(for: now)).day ?? 0
        return days + 1
    }
}
