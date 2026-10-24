import Dependencies
import Foundation

/// CoreMotion's `CMAltimeter` wrapped as a struct-of-closures (DI parity with
/// `Pedometer`). `startUpdates()` yields the cumulative elevation gain in
/// metres each time the barometer reports a fresh reading.
nonisolated struct Altimeter: Sendable {
    var startUpdates: @Sendable () -> AsyncStream<Double>
    var stop: @Sendable () -> Void
}

nonisolated extension Altimeter: DependencyKey {
    static let previewValue = Altimeter(
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
        startUpdates: { AsyncStream { $0.finish() } },
        stop: {}
    )
}

nonisolated extension DependencyValues {
    var altimeter: Altimeter {
        get { self[Altimeter.self] }
        set { self[Altimeter.self] = newValue }
    }
}
