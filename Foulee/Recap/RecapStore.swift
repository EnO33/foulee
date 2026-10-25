import Dependencies
import FouleeKit
import Foundation
import Observation

/// Loads the Bilan (issues #344, #350, #363, #444, #445): the recap of the
/// week and the month in progress, their outings day by day, and — for the
/// screen that pages back — every period of the last twelve months, with the
/// streak and the year's totals.
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
    /// The streak, its record and the year behind them (issue #445); only
    /// read with the history.
    private(set) var streak: StreakSummary?
    private(set) var isLoading = false
    private(set) var lastError: String?

    /// What the last read returned, kept to work out any period on demand.
    private var source: Source?
    /// What the last read was asked for, so a merge reads the same again.
    @ObservationIgnored private var lastRequest: Request?
    /// Periods already worked out: paging back and forth recomputes nothing.
    @ObservationIgnored private var cache: [RecapPeriod: RecapPeriodContent] = [:]

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    @ObservationIgnored
    @Dependency(\.date) private var date

    @ObservationIgnored
    @Dependency(\.outingMerges) private var outingMerges

    /// `waterGoalML` is the hydration goal, `nil` while hydration is off.
    ///
    /// `withHistory` reaches back `RecapPeriod.historyMonths` for the screen
    /// that pages (issue #444), and at least `StreakCalculator.historyWindowDays`
    /// so its record is the home's (issue #445); the home's card only needs the
    /// periods in progress, and reads no further.
    func load(goalMinutes: Int, activeDays: Set<Weekday>, waterGoalML: Int? = nil, withHistory: Bool = false) async {
        lastRequest = Request(goalMinutes: goalMinutes, activeDays: activeDays, waterGoalML: waterGoalML, withHistory: withHistory)
        isLoading = true
        defer { isLoading = false }
        let now = date.now
        let periods = RecapPeriod.Kind.allCases.map { RecapPeriod.current($0, at: now) }
        let reach = withHistory ? periods + RecapPeriod.Kind.allCases.map { RecapPeriod.earliest($0, at: now) } : periods
        let covered = Self.daysBack(covering: reach, from: now)
        let daysBack = withHistory ? max(covered, StreakCalculator.historyWindowDays) : covered
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
            streak = withHistory
                ? StreakSummary.make(history: inputs.minutes, goalMinutes: goalMinutes, activeDays: activeDays, today: now)
                : nil
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

    /// The outings of the last read `outing` can be merged with (issue #552).
    func mergeNeighbours(of outing: WorkoutSummary) -> (previous: WorkoutSummary?, next: WorkoutSummary?) {
        OutingMerges.neighbours(of: outing, in: source?.inputs.workouts ?? [])
    }

    /// Whether `outing` is one the wearer merged, and can separate.
    func isMerged(_ outing: WorkoutSummary) -> Bool {
        OutingMerges.isMerged(outing, in: outingMerges.read())
    }

    /// Make `outing` and `other` one outing (issue #549), then read the
    /// Bilan again: Santé is not rewritten, the merge applies when it is read.
    func merge(_ outing: WorkoutSummary, with other: WorkoutSummary) async {
        guard OutingMerges.canMerge(outing, other) else { return }
        outingMerges.write(OutingMerges.merging(outing, other, in: outingMerges.read()))
        await reload()
    }

    /// Undo the merge `outing` stands for, then read the Bilan again.
    func separate(_ outing: WorkoutSummary) async {
        let merges = outingMerges.read()
        guard OutingMerges.isMerged(outing, in: merges) else { return }
        outingMerges.write(OutingMerges.separating(outing, in: merges))
        await reload()
    }

    private func reload() async {
        guard let request = lastRequest else { return }
        await load(
            goalMinutes: request.goalMinutes,
            activeDays: request.activeDays,
            waterGoalML: request.waterGoalML,
            withHistory: request.withHistory
        )
    }

    private struct Request {
        var goalMinutes: Int
        var activeDays: Set<Weekday>
        var waterGoalML: Int?
        var withHistory: Bool
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
