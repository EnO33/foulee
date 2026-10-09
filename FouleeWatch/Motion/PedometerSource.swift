import CoreMotion
import Foundation

/// What the pedometer says about the wearer's rhythm right now (issue #331).
///
/// Apple's own estimate, not ours: `CMPedometerData.currentCadence` and
/// `currentPace` are computed by the system from the accelerometer and
/// calibrated against the GPS of past outings. They replace a cadence this app
/// used to derive by dividing two `HKLiveWorkoutBuilder` sums read at the
/// moment they were *delivered* — and HealthKit delivers steps in uneven
/// batches, so a three-second window could hold two seconds of strides and
/// read a run as a walk.
struct PedometerReading: Equatable, Sendable {
    /// The end of the interval the estimate describes — the pedometer's own
    /// timestamp, never the moment this process was told.
    var date: Date
    /// Steps per second, or `nil` when the pedometer had no opinion.
    var cadence: Double?
    /// Seconds per metre, or `nil` when the pedometer had no opinion.
    var pace: Double?

    /// Metres per second, derived from `pace`. `nil` for a missing or
    /// non-positive pace, which a division would turn into infinity.
    var speed: Double? {
        guard let pace, pace > 0 else { return nil }
        return 1 / pace
    }
}

/// The app's only contact with `CMPedometer` on the watch, as three closures.
///
/// The same seam as `MotionActivitySource`, for the same reason: neither
/// `CMPedometer.isCadenceAvailable()` nor `isPaceAvailable()` is true on a
/// simulator, so the real one would leave everything downstream reachable only
/// on a wrist. It needs no permission of its own — « Mouvements et forme »
/// covers both, and the activity stream already asks for it.
struct PedometerSource: Sendable {
    var isAvailable: @MainActor () -> Bool
    /// Opens the stream from `start`; `handler` is called once per update, on
    /// whatever queue CoreMotion picks.
    var openStream: @MainActor (_ start: Date, _ handler: @escaping @Sendable (PedometerReading) -> Void) -> Void
    var closeStream: @MainActor () -> Void

    @MainActor
    static func live() -> PedometerSource {
        let pedometer = CMPedometer()
        return PedometerSource(
            isAvailable: { CMPedometer.isCadenceAvailable() && CMPedometer.isPaceAvailable() },
            openStream: { start, handler in
                pedometer.startUpdates(from: start) { data, error in
                    // Converted to a value at once: `CMPedometerData` is a
                    // reference type this app must not hold on to.
                    guard let data else {
                        if let error {
                            FouleeLog.detection.error(
                                "podomètre muet : \(error.localizedDescription, privacy: .public)"
                            )
                        }
                        return
                    }
                    handler(PedometerReading(
                        date: data.endDate,
                        cadence: data.currentCadence?.doubleValue,
                        pace: data.currentPace?.doubleValue
                    ))
                }
            },
            closeStream: { pedometer.stopUpdates() }
        )
    }
}
