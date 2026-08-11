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
    /// Steps recorded over a past interval, or `nil` when the device cannot
    /// say (issue #247).
    ///
    /// A **query**, not a second subscription: `Pedometer+Live` holds one
    /// shared `CMPedometer`, and a second `startUpdates` would replace the
    /// first's handler while `onTermination` killed both. `queryPedometerData`
    /// touches neither.
    ///
    /// `nil` rather than `0`, because the two mean opposite things: zero steps
    /// over a stretch is a measurement, and « the device would not answer » is
    /// not. One credits nothing; the other must fall back to the estimate that
    /// existed before.
    var steps: @Sendable (_ from: Date, _ to: Date) async -> Int?
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
        stop: {},
        steps: { from, to in Int(to.timeIntervalSince(from) * 1.8) }
    )

    static let testValue = Pedometer(
        startUpdates: { _ in AsyncStream { $0.finish() } },
        stop: {},
        steps: { _, _ in nil }
    )
}

extension DependencyValues {
    var pedometer: Pedometer {
        get { self[Pedometer.self] }
        set { self[Pedometer.self] = newValue }
    }
}
