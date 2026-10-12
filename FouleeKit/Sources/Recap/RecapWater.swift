import FouleeKit
import Foundation

/// The water side of a recap (issue #356): how much a day on average, how
/// many days held the goal, and the average of the period before. Pure, from
/// the daily `dietaryWater` totals, like `Recap.make` from the minutes.
nonisolated public struct RecapWater: Equatable, Sendable {
    public var averageML: Int
    public var previousAverageML: Int
    public var goalDaysMet: Int
    /// Days in the period — the goal days' denominator.
    public var dayCount: Int
    public var goalML: Int

    public static func make(
        period: RecapPeriod,
        series: [MetricPoint],
        goalML: Int,
        calendar: Calendar = .iso8601Monday
    ) -> RecapWater {
        let byDay = Dictionary(series.map { (calendar.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: +)

        func totals(in range: RecapPeriod) -> [Double] {
            range.days(calendar: calendar).map { byDay[$0] ?? 0 }
        }

        func average(_ totals: [Double]) -> Int {
            totals.isEmpty ? 0 : Int((totals.reduce(0, +) / Double(totals.count)).rounded())
        }

        let days = totals(in: period)
        return RecapWater(
            averageML: average(days),
            previousAverageML: average(totals(in: period.previous(calendar: calendar))),
            goalDaysMet: days.filter { HydrationMath.reachedGoal(intakeML: Int($0.rounded()), goalML: goalML) }.count,
            dayCount: days.count,
            goalML: goalML
        )
    }

    public init(
        averageML: Int,
        previousAverageML: Int,
        goalDaysMet: Int,
        dayCount: Int,
        goalML: Int
    ) {
        self.averageML = averageML
        self.previousAverageML = previousAverageML
        self.goalDaysMet = goalDaysMet
        self.dayCount = dayCount
        self.goalML = goalML
    }
}
