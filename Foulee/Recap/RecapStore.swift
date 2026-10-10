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
    /// Each period's water (issue #356); empty while hydration is off, or when
    /// the water could not be read — the recap stands without it.
    private(set) var water: [RecapPeriod.Kind: RecapWater] = [:]
    private(set) var isLoading = false
    private(set) var lastError: String?

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    @ObservationIgnored
    @Dependency(\.date) private var date

    /// `waterGoalML` is the hydration goal, `nil` while hydration is off.
    func load(goalMinutes: Int, activeDays: Set<Weekday>, waterGoalML: Int? = nil) async {
        isLoading = true
        defer { isLoading = false }
        let now = date.now
        let periods = RecapPeriod.Kind.allCases.map { RecapPeriod.current($0, at: now) }
        let daysBack = Self.daysBack(covering: periods, from: now)
        // Alongside the recap's own read, and never in its way.
        async let waterSeries = Self.readWater(from: healthKit, daysBack: daysBack, isEnabled: waterGoalML != nil)
        do {
            let inputs = try await Self.readInputs(from: healthKit, daysBack: daysBack)
            recaps = Dictionary(uniqueKeysWithValues: periods.map {
                ($0.kind, Recap.make(period: $0, from: inputs, goalMinutes: goalMinutes, activeDays: activeDays))
            })
            outings = Dictionary(uniqueKeysWithValues: periods.map {
                ($0.kind, OutingDay.days(in: $0, from: inputs.workouts))
            })
            if let series = await waterSeries, let waterGoalML {
                water = Dictionary(uniqueKeysWithValues: periods.map {
                    ($0.kind, RecapWater.make(period: $0, series: series, goalML: waterGoalML))
                })
            } else {
                water = [:]
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The daily water totals, or `nil` when hydration is off or Santé refused.
    private static func readWater(from healthKit: HealthKitClient, daysBack: Int, isEnabled: Bool) async -> [MetricPoint]? {
        guard isEnabled else { return nil }
        return try? await healthKit.waterSeries(daysBack)
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
