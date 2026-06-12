@preconcurrency import CoreMotion
import Foundation

extension Pedometer {
    /// Real CoreMotion-backed implementation. One shared `CMPedometer` instance
    /// — `stop()` halts updates without invalidating the stream's continuation
    /// so callers can decide whether to restart.
    static let liveValue: Pedometer = {
        let pedometer = CMPedometer()
        return Pedometer(
            startUpdates: { from in
                AsyncStream { continuation in
                    pedometer.startUpdates(from: from) { data, _ in
                        guard let data else { return }
                        continuation.yield(PedometerSample(
                            steps: data.numberOfSteps.intValue,
                            distanceMeters: data.distance?.doubleValue ?? 0
                        ))
                    }
                    continuation.onTermination = { _ in pedometer.stopUpdates() }
                }
            },
            stop: { pedometer.stopUpdates() }
        )
    }()
}
