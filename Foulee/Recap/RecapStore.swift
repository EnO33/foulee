import Dependencies
import FouleeKit
import Foundation
import Observation

/// Loads the Bilan (issues #344, #350, #363, #444): the recap of the week and
/// the month in progress, their outings day by day, and — for the screen that
/// pages back — every period of the last twelve months.
///
/// One read of Santé covers it all: the series reach back to the start of the
/// earliest period compared. Paging reads nothing more; each period is worked
/// out from that one read when it is first shown (`content(for:)`).
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

    /// What the last read returned, kept to work out any period on demand.
    private var source: Source?
    /// Periods already worked out: paging back and forth recomputes nothing.
    @ObservationIgnored private var cache: [RecapPeriod: RecapPeriodContent] = [:]

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    @ObservationIgnored
    @Dependency(\.date) private var date

    /// `waterGoalML` is the hydration goal, `nil` while hydration is off.
    ///
    /// `withHistory` reaches back `RecapPeriod.historyMonths` for the screen
    /// that pages (issue #444); the home's card only needs the periods in
    /// progress, and reads no further.
    func load(goalMinutes: Int, activeDays: Set<Weekday>, waterGoalML: Int? = nil, withHistory: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        let now = date.now
        let periods = RecapPeriod.Kind.allCases.map { RecapPeriod.current($0, at: now) }
        let reach = withHistory ? periods + RecapPeriod.Kind.allCases.map { RecapPeriod.earliest($0, at: now) } : periods
        let daysBack = Self.daysBack(covering: reach, from: now)
        // Alongside the recap's own read, and never in its way.
        async let waterSeries = Self.readWater(from: healthKit, daysBack: daysBack, isEnabled: waterGoalML != nil)
        do {
            let inputs = try await Self.readInputs(from: healthKit, daysBack: daysBack)
            let series = await waterSeries
            source = Source(
                inputs: inputs,
                water: waterGoalML.flatMap { goal in series.map { ($0, goal) } },
                goalMinutes: goalMinutes,
                activeDays: activeDays
            )
            cache = [:]
            let contents = periods.compactMap { content(for: $0) }
            recaps = Dictionary(uniqueKeysWithValues: contents.map { ($0.recap.period.kind, $0.recap) })
            outings = Dictionary(uniqueKeysWithValues: contents.map { ($0.recap.period.kind, $0.outings) })
            water = Dictionary(uniqueKeysWithValues: contents.compactMap { content in
                content.water.map { (content.recap.period.kind, $0) }
            })
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The recap, outings and water of any period the last read covers, or
    /// `nil` before it has returned.
    func content(for period: RecapPeriod) -> RecapPeriodContent? {
        if let cached = cache[period] { return cached }
        guard let source else { return nil }
        let content = RecapPeriodContent(
            recap: Recap.make(
                period: period,
                from: source.inputs,
                goalMinutes: source.goalMinutes,
                activeDays: source.activeDays
            ),
            outings: OutingDay.days(in: period, from: source.inputs.workouts),
            water: source.water.map { RecapWater.make(period: period, series: $0.series, goalML: $0.goalML) }
        )
        cache[period] = content
        return content
    }

    private struct Source {
        var inputs: Recap.Inputs
        var water: (series: [MetricPoint], goalML: Int)?
        var goalMinutes: Int
        var activeDays: Set<Weekday>
    }

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

/// One period of the Bilan, as the screen draws it (issue #444).
struct RecapPeriodContent {
    let recap: Recap
    /// The period's days with their outings, in the order of the recap's days.
    let outings: [OutingDay]
    /// `nil` while hydration is off, or when the water could not be read.
    let water: RecapWater?
}
