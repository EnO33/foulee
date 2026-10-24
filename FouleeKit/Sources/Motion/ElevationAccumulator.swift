import Foundation

/// Turns a stream of (signed) relative-altitude readings into cumulative
/// elevation *gain* — the sum of the positive changes, ignoring descents.
/// Pure + value type so it's trivially unit-testable. In the kit since the
/// watch measures the climb too (issue #535).
nonisolated public struct ElevationAccumulator: Sendable {
    private var last: Double?
    public private(set) var gain: Double = 0

    public init() {}

    /// Feed the next reading; returns the running gain in metres.
    public mutating func add(relativeAltitude: Double) -> Double {
        defer { last = relativeAltitude }
        guard let last else { return gain }
        let delta = relativeAltitude - last
        if delta > 0 { gain += delta }
        return gain
    }
}
