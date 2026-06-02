import Foundation

/// One time-bucketed value of a `WalkMetric` — a calendar day (week/month
/// ranges) or an hour (today range). `value` is already in the metric's
/// display unit (steps, minutes, km, kcal).
struct MetricPoint: Equatable, Sendable, Identifiable {
    var date: Date
    var value: Double

    var id: Date { date }
}
