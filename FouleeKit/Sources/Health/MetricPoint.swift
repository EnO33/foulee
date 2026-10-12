import Foundation

/// One time-bucketed value of a `WalkMetric` — a calendar day (week/month
/// ranges) or an hour (today range). `value` is already in the metric's
/// display unit (steps, minutes, km, kcal).
nonisolated public struct MetricPoint: Equatable, Sendable, Identifiable {
    public var date: Date
    public var value: Double

    public var id: Date { date }

    public init(
        date: Date,
        value: Double
    ) {
        self.date = date
        self.value = value
    }
}
