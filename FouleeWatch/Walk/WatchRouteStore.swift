@preconcurrency import CoreLocation
import Observation

/// The app's contact with CoreLocation during an outing, as two closures
/// (issue #312).
///
/// Hand-written for the same reason as `MotionActivitySource`: the watch
/// target links no dependency container, and through the real CoreLocation
/// the store's lifetime rules would only be reachable on a wrist.
struct WatchRouteSource: Sendable {
    /// Asks once, answers whether a position may be read.
    var requestAuthorization: @MainActor () async -> Bool
    /// Usable fixes until the consumer stops iterating.
    var updates: @Sendable () -> AsyncStream<CLLocation>

    static let live = WatchRouteSource(
        requestAuthorization: { await RouteRecorder.shared.requestAuthorization() },
        updates: { RouteRecorder.updates() }
    )
}

/// The path walked so far: drawn on the session's « Plan » page, and saved
/// with each leg's workout (issue #312).
///
/// Its own observable rather than a field of `WatchWorkoutMetrics`: the metrics
/// are rebuilt on every HealthKit batch and compared whole, and a route grows
/// to a thousand points over an hour. Kept here, only the page that draws it
/// redraws when it grows.
///
/// **Writes nothing itself.** It holds the outing's fixes; `WatchWorkoutStore`
/// hands them to each leg as it is saved, and whatever happens here, the
/// outing goes on.
@MainActor
@Observable
final class WatchRouteStore {
    /// Every usable fix of the outing, oldest first. Whole `CLLocation`s, not
    /// coordinates: Santé wants each fix's time, accuracy and altitude.
    private(set) var locations: [CLLocation] = []
    /// The wearer refused location access — the page says so instead of
    /// waiting forever for a first fix.
    private(set) var isDenied = false

    @ObservationIgnored private let source: WatchRouteSource
    @ObservationIgnored private var recording: Task<Void, Never>?

    /// What the map draws. Derived rather than stored next to `locations`,
    /// so the two can never disagree.
    var coordinates: [CLLocationCoordinate2D] { locations.map(\.coordinate) }

    init(source: WatchRouteSource = .live) {
        self.source = source
    }

    /// Start a fresh route. Asks for access the first time — at the start of an
    /// outing, the moment the request explains itself.
    func start() {
        reset()
        recording = Task { [weak self, source] in
            let granted = await source.requestAuthorization()
            // The outing may have ended while the prompt was on screen.
            guard !Task.isCancelled else { return }
            guard granted else {
                self?.isDenied = true
                FouleeLog.route.notice("tracé : position refusée")
                return
            }
            for await fix in source.updates() {
                self?.locations.append(fix)
            }
        }
    }

    /// Stop recording and keep what was drawn — the outing is over, not
    /// forgotten. Idempotent.
    func stop() {
        recording?.cancel()
        recording = nil
    }

    /// Forget the route, back to the home screen.
    func reset() {
        stop()
        locations = []
        isDenied = false
    }
}
