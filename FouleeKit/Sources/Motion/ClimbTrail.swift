import Foundation

/// The outing's climb over time, to give each leg its own (issue #535).
///
/// The barometer runs for the whole outing, but a change of sport closes a
/// leg at a boundary dated in the past (ADR 0002, D7): the leg's climb is
/// what the outing had gained at its end, less what it had gained at its
/// start — read here rather than at the moment the leg is saved.
nonisolated public struct ClimbTrail: Equatable, Sendable {
    nonisolated struct Sample: Equatable, Sendable {
        var date: Date
        var gain: Double
    }

    private var samples: [Sample] = []

    public init() {}

    /// The outing's cumulative gain, in metres, as of `date`. Readings come in
    /// order; one out of order is dropped rather than rewriting the past.
    public mutating func record(_ gain: Double, at date: Date) {
        if let last = samples.last, date < last.date { return }
        samples.append(Sample(date: date, gain: gain))
    }

    /// The whole outing's climb so far.
    public var total: Double { samples.last?.gain ?? 0 }

    /// The climb between two instants of the outing.
    public func climb(from start: Date, to end: Date) -> Double {
        max(0, gain(at: end) - gain(at: start))
    }

    /// The gain of the last reading at or before `date`; 0 before the first.
    private func gain(at date: Date) -> Double {
        samples.last { $0.date <= date }?.gain ?? 0
    }
}
