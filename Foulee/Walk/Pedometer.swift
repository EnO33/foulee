import Dependencies
import Foundation

/// Sample emitted by `Pedometer.startUpdates(from:)` each time CoreMotion
/// has a fresh delta.
struct PedometerSample: Equatable, Sendable {
    var steps: Int
    var distanceMeters: Double
}

/// CoreMotion's `CMPedometer` wrapped as a struct-of-closures for DI parity
/// with `HealthKitClient`. `startUpdates(from:)` returns an `AsyncStream` so
/// the store can `for-await` cleanly and cancel on session stop.
struct Pedometer: Sendable {
    var startUpdates: @Sendable (_ from: Date) -> AsyncStream<PedometerSample>
    var stop: @Sendable () -> Void
}

extension Pedometer: DependencyKey {
    static let previewValue = Pedometer(
        startUpdates: { _ in
            AsyncStream { continuation in
                Task {
                    var steps = 0
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        steps += 25
                        continuation.yield(PedometerSample(
                            steps: steps,
                            distanceMeters: Double(steps) * 0.78
                        ))
                    }
                    continuation.finish()
                }
            }
        },
        stop: {}
    )

    static let testValue = Pedometer(
        startUpdates: { _ in AsyncStream { $0.finish() } },
        stop: {}
    )
}

extension DependencyValues {
    var pedometer: Pedometer {
        get { self[Pedometer.self] }
        set { self[Pedometer.self] = newValue }
    }
}
