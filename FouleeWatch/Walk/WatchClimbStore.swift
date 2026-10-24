@preconcurrency import CoreMotion
import FouleeKit
import Foundation

/// The barometer during an outing, as one closure (issue #535): the
/// cumulative climb in metres, each time it changes.
///
/// Hand-written like `WatchRouteSource`: the watch target links no
/// dependency container, and the real `CMAltimeter` only answers on a wrist.
struct WatchClimbSource: Sendable {
    var updates: @Sendable () -> AsyncStream<Double>

    static let live = WatchClimbSource {
        AsyncStream { continuation in
            // No barometer — an older watch, the simulator — is no climb, not
            // a failure: the outing records everything else.
            guard CMAltimeter.isRelativeAltitudeAvailable() else {
                continuation.finish()
                return
            }
            let altimeter = CMAltimeter()
            var accumulator = ElevationAccumulator()
            altimeter.startRelativeAltitudeUpdates(to: .main) { data, _ in
                guard let data else { return }
                continuation.yield(accumulator.add(relativeAltitude: data.relativeAltitude.doubleValue))
            }
            continuation.onTermination = { _ in altimeter.stopRelativeAltitudeUpdates() }
        }
    }

    /// No barometer at all: the tests, which date the climb themselves.
    static let inert = WatchClimbSource { AsyncStream { $0.finish() } }
}

/// The outing's climb over time (issue #535): the screen reads its total,
/// and each leg's workout is stamped with its own share as it is saved.
///
/// Spans every leg, as the route does: a change of sport is not a change of
/// slope. **Writes nothing itself**, and whatever happens here, the outing
/// goes on.
@MainActor
final class WatchClimbStore {
    private(set) var trail = ClimbTrail()

    private let source: WatchClimbSource
    private var recording: Task<Void, Never>?

    init(source: WatchClimbSource = .live) {
        self.source = source
    }

    /// Start a fresh climb, each reading dated by `clock`.
    func start(clock: @escaping @MainActor () -> Date) {
        stop()
        trail = ClimbTrail()
        recording = Task { [weak self, source] in
            for await gain in source.updates() {
                self?.record(gain, at: clock())
            }
        }
    }

    /// The outing's climb as of `date`.
    func record(_ gain: Double, at date: Date) {
        trail.record(gain, at: date)
    }

    /// Stop measuring and keep what was climbed. Idempotent.
    func stop() {
        recording?.cancel()
        recording = nil
    }
}
