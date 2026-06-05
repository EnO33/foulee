import Dependencies
import Foundation

/// Turns a stream of (signed) relative-altitude readings into cumulative
/// elevation *gain* — the sum of the positive changes, ignoring descents.
/// Pure + value type so it's trivially unit-testable.
struct ElevationAccumulator {
    private var last: Double?
    private(set) var gain: Double = 0

    /// Feed the next reading; returns the running gain in metres.
    mutating func add(relativeAltitude: Double) -> Double {
        defer { last = relativeAltitude }
        guard let last else { return gain }
        let delta = relativeAltitude - last
        if delta > 0 { gain += delta }
        return gain
    }
}

/// CoreMotion's `CMAltimeter` wrapped as a struct-of-closures (DI parity with
/// `Pedometer`). `startUpdates()` yields the cumulative elevation gain in
/// metres each time the barometer reports a fresh reading.
struct Altimeter: Sendable {
    var isAvailable: @Sendable () -> Bool
    var startUpdates: @Sendable () -> AsyncStream<Double>
    var stop: @Sendable () -> Void
}

extension Altimeter: DependencyKey {
    static let previewValue = Altimeter(
        isAvailable: { true },
        startUpdates: {
            AsyncStream { continuation in
                Task {
                    var gain = 0.0
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        gain += 1.5
                        continuation.yield(gain)
                    }
                    continuation.finish()
                }
            }
        },
        stop: {}
    )

    static let testValue = Altimeter(
        isAvailable: { false },
        startUpdates: { AsyncStream { $0.finish() } },
        stop: {}
    )
}

extension DependencyValues {
    var altimeter: Altimeter {
        get { self[Altimeter.self] }
        set { self[Altimeter.self] = newValue }
    }
}
