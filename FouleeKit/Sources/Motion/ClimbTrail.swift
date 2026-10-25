import Foundation

/// The outing's climb and descent over time, to give each leg its own
/// (issues #535, #564).
///
/// The barometer runs for the whole outing, but a change of sport closes a
/// leg at a boundary dated in the past (ADR 0002, D7): the leg's climb is
/// what the outing had gained at its end, less what it had gained at its
/// start — read here rather than at the moment the leg is saved. The descent
/// alike.
nonisolated public struct ClimbTrail: Equatable, Sendable {
    nonisolated struct Sample: Equatable, Sendable {
        var date: Date
        var elevation: Elevation
    }

    private var samples: [Sample] = []

    public init() {}

    /// The outing's cumulative climb and descent as of `date`. Readings come
    /// in order; one out of order is dropped rather than rewriting the past.
    public mutating func record(_ elevation: Elevation, at date: Date) {
        if let last = samples.last, date < last.date { return }
        samples.append(Sample(date: date, elevation: elevation))
    }

    /// The whole outing's climb and descent so far.
    public var total: Elevation { samples.last?.elevation ?? .zero }

    /// The climb and descent between two instants of the outing.
    public func elevation(from start: Date, to end: Date) -> Elevation {
        let before = elevation(at: start)
        let after = elevation(at: end)
        return Elevation(
            ascent: max(0, after.ascent - before.ascent),
            descent: max(0, after.descent - before.descent)
        )
    }

    /// The last reading at or before `date`; nothing before the first.
    private func elevation(at date: Date) -> Elevation {
        samples.last { $0.date <= date }?.elevation ?? .zero
    }
}
