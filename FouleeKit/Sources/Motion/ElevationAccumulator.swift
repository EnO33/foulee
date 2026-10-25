import Foundation

/// Turns a stream of (signed) relative-altitude readings into the climb and
/// the descent of an outing, the barometer's noise left out (issue #563).
/// Pure + value type so it's trivially unit-testable. In the kit since the
/// watch measures the climb too (issue #535).
///
/// **A threshold, not every delta.** The barometer reads about once a second
/// and never stands still: tenths of a metre up, tenths down, all the time.
/// Summing every rise counted each of those, and an hour on the flat came out
/// at hundreds of metres climbed. A change only counts once the altitude has
/// moved `threshold` away from the last point kept — the way sports watches
/// measure it — and then it counts whole, so a steady slope loses nothing but
/// its last few metres.
nonisolated public struct ElevationAccumulator: Sendable {
    /// How far the altitude must move from the last point kept before the
    /// move counts. Above the barometer's noise, below any slope a walker
    /// would call one.
    public static let threshold: Double = 3

    /// The last altitude a change was counted from.
    private var anchor: Double?
    public private(set) var gain: Double = 0
    /// The descent, measured the same way.
    private(set) var loss: Double = 0

    public init() {}

    /// Feed the next reading; returns the running gain in metres.
    public mutating func add(relativeAltitude: Double) -> Double {
        guard let anchor else {
            self.anchor = relativeAltitude
            return gain
        }
        let delta = relativeAltitude - anchor
        guard abs(delta) >= Self.threshold else { return gain }
        if delta > 0 {
            gain += delta
        } else {
            loss -= delta
        }
        self.anchor = relativeAltitude
        return gain
    }
}
