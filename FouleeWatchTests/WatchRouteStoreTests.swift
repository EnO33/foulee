import CoreLocation
import Testing
@testable import FouleeWatch

/// Scriptable stand-in for `RouteRecorder` (issue #312): answers the
/// authorization question as told, and hands out a stream the test feeds.
@MainActor
final class FakeRouteSource {
    var granted = true
    private(set) var authorizationRequests = 0
    private(set) var openedStreams = 0
    private(set) var terminatedStreams = 0
    private var continuation: AsyncStream<CLLocation>.Continuation?

    var source: WatchRouteSource {
        WatchRouteSource(
            requestAuthorization: {
                self.authorizationRequests += 1
                return self.granted
            },
            updates: {
                AsyncStream { continuation in
                    continuation.onTermination = { _ in
                        Task { @MainActor in self.terminatedStreams += 1 }
                    }
                    Task { @MainActor in
                        self.continuation = continuation
                        self.openedStreams += 1
                    }
                }
            }
        )
    }

    func deliver(latitude: Double, longitude: Double) {
        continuation?.yield(CLLocation(latitude: latitude, longitude: longitude))
    }
}

extension WatchRouteSource {
    /// No GPS and no prompt: for suites that are not about the route. Without
    /// it they would reach the real `RouteRecorder` and raise a location sheet
    /// on the test host.
    static let inert = WatchRouteSource(
        requestAuthorization: { false },
        updates: { AsyncStream { $0.finish() } }
    )
}

@MainActor
@Suite("Watch route store")
struct WatchRouteStoreTests {
    @Test("Fixes are drawn in the order they arrive")
    func recordsFixes() async {
        let fake = FakeRouteSource()
        let store = WatchRouteStore(source: fake.source)
        store.start()
        await waitUntil { fake.openedStreams == 1 }

        fake.deliver(latitude: 48.8634, longitude: 2.3270)
        fake.deliver(latitude: 48.8638, longitude: 2.3285)

        await waitUntil { store.coordinates.count == 2 }
        #expect(store.coordinates.first?.latitude == 48.8634)
        #expect(store.coordinates.last?.longitude == 2.3285)
        #expect(store.isDenied == false)
    }

    /// The page has to say *why* nothing is drawn — waiting for GPS resolves
    /// on its own, a refusal never does.
    @Test("A refusal is reported and opens no stream")
    func refusal() async {
        let fake = FakeRouteSource()
        fake.granted = false
        let store = WatchRouteStore(source: fake.source)
        store.start()

        await waitUntil { store.isDenied }
        #expect(fake.openedStreams == 0)
    }

    /// The recap is lot 3 of the issue, and it draws what was recorded: ending
    /// the outing stops the GPS but must not wipe the route.
    @Test("stop() closes the stream and keeps the route")
    func stopKeepsRoute() async {
        let fake = FakeRouteSource()
        let store = WatchRouteStore(source: fake.source)
        store.start()
        await waitUntil { fake.openedStreams == 1 }
        fake.deliver(latitude: 48.8634, longitude: 2.3270)
        await waitUntil { store.coordinates.count == 1 }

        store.stop()

        await waitUntil { fake.terminatedStreams == 1 }
        fake.deliver(latitude: 48.8638, longitude: 2.3285)
        #expect(store.coordinates.count == 1)
    }

    @Test("reset() forgets the route and the refusal")
    func resetClears() async {
        let fake = FakeRouteSource()
        fake.granted = false
        let store = WatchRouteStore(source: fake.source)
        store.start()
        await waitUntil { store.isDenied }

        store.reset()

        #expect(store.isDenied == false)
        #expect(store.coordinates.isEmpty)
    }

    /// A second outing must not start drawn on top of the first one.
    @Test("A new start begins from an empty route, on a fresh stream")
    func restartClears() async {
        let fake = FakeRouteSource()
        let store = WatchRouteStore(source: fake.source)
        store.start()
        await waitUntil { fake.openedStreams == 1 }
        fake.deliver(latitude: 48.8634, longitude: 2.3270)
        await waitUntil { store.coordinates.count == 1 }

        store.start()

        #expect(store.coordinates.isEmpty)
        await waitUntil { fake.openedStreams == 2 && fake.terminatedStreams == 1 }
    }
}

/// The accuracy rule both platforms share (issue #312).
@Suite("Route fix accuracy")
struct RouteRecorderAccuracyTests {
    private func fix(accuracy: CLLocationAccuracy) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 48.86, longitude: 2.33),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            timestamp: .now
        )
    }

    @Test("A GPS-grade fix is kept", arguments: [0.0, 5, 50])
    func keepsPreciseFixes(accuracy: CLLocationAccuracy) {
        #expect(RouteRecorder.isUsable(fix(accuracy: accuracy)))
    }

    /// Negative is CoreLocation's « invalid »; past 50 m is a guess that would
    /// draw a spike on the map.
    @Test("An invalid or coarse fix is dropped", arguments: [-1.0, 50.1, 65, 1_000])
    func dropsCoarseFixes(accuracy: CLLocationAccuracy) {
        #expect(RouteRecorder.isUsable(fix(accuracy: accuracy)) == false)
    }
}

/// The route follows the outing's lifetime, not a leg's (issue #312).
@MainActor
@Suite("Workout store drives the route")
struct WatchWorkoutRouteLifecycleTests {
    @Test("An outing opens the route; « Terminer » stops it; home forgets it")
    func followsTheOuting() async {
        let stub = WorkoutHealthKitStub()
        let fake = FakeRouteSource()
        let store = stub.makeStore(route: WatchRouteStore(source: fake.source))

        await store.start(activity: .walking)
        await waitUntil { fake.openedStreams == 1 }
        fake.deliver(latitude: 48.8634, longitude: 2.3270)
        await waitUntil { store.route.coordinates.count == 1 }

        await store.stop()
        await waitUntil { fake.terminatedStreams == 1 }
        #expect(store.route.coordinates.count == 1)

        store.reset()
        #expect(store.route.coordinates.isEmpty)
    }

    @Test("A session that dies on its own lets the GPS go")
    func failureStopsTheRoute() async {
        let stub = WorkoutHealthKitStub()
        let fake = FakeRouteSource()
        let store = stub.makeStore(route: WatchRouteStore(source: fake.source))
        await store.start(activity: .walking)
        await waitUntil { fake.openedStreams == 1 }

        store.handleSessionFailure("boom")

        await waitUntil { fake.terminatedStreams == 1 }
    }

    /// No session, no prompt: a start HealthKit refuses must not ask for the
    /// wearer's position on its way out.
    @Test("A refused start never asks for location")
    func refusedStartAsksNothing() async {
        let stub = WorkoutHealthKitStub()
        stub.startError = StubError()
        let fake = FakeRouteSource()
        let store = stub.makeStore(route: WatchRouteStore(source: fake.source))

        await store.start(activity: .walking)

        #expect(fake.authorizationRequests == 0)
    }
}

/// Saving the route with each leg's workout (issue #312, lot 2).
@MainActor
@Suite("Route saved with the workout")
struct WatchWorkoutRouteSaveTests {
    private func fix(at date: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 48.86, longitude: 2.33),
            altitude: 35,
            horizontalAccuracy: 5,
            verticalAccuracy: 3,
            timestamp: date
        )
    }

    /// A split is dated at the detected boundary, in the past: the fixes after
    /// it belong to the next leg, and Santé would draw them on the wrong one.
    @Test("A leg keeps only the fixes inside its own dates, bounds included")
    func legSlice() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let end = start.addingTimeInterval(600)
        let fixes = [-1.0, 0, 300, 600, 601].map { fix(at: start.addingTimeInterval($0)) }

        let leg = WatchWorkoutHealthKit.routeFixes(fixes, from: start, to: end)

        #expect(leg.map(\.timestamp) == [0.0, 300, 600].map { start.addingTimeInterval($0) })
    }

    @Test("An inverted range yields nothing rather than trapping")
    func invertedRange() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let fixes = [fix(at: start)]
        #expect(WatchWorkoutHealthKit.routeFixes(fixes, from: start, to: start.addingTimeInterval(-1)).isEmpty)
    }

    @Test("« Terminer » hands the outing's fixes to the save")
    func stopHandsTheRoute() async {
        let stub = WorkoutHealthKitStub()
        let fake = FakeRouteSource()
        let store = stub.makeStore(route: WatchRouteStore(source: fake.source))
        await store.start(activity: .walking)
        await waitUntil { fake.openedStreams == 1 }
        fake.deliver(latitude: 48.8634, longitude: 2.3270)
        fake.deliver(latitude: 48.8638, longitude: 2.3285)
        await waitUntil { store.route.locations.count == 2 }

        await store.stop()

        #expect(stub.finishedRoutes.map(\.count) == [2])
    }

    /// A retry must save the same route the first attempt would have.
    @Test("A retried save carries the route again")
    func retryHandsTheRoute() async {
        let stub = WorkoutHealthKitStub()
        let fake = FakeRouteSource()
        let store = stub.makeStore(route: WatchRouteStore(source: fake.source))
        await store.start(activity: .walking)
        await waitUntil { fake.openedStreams == 1 }
        fake.deliver(latitude: 48.8634, longitude: 2.3270)
        await waitUntil { store.route.locations.count == 1 }
        stub.finishError = StubError()
        await store.stop()
        stub.finishError = nil

        await store.retrySave()

        #expect(stub.finishedRoutes.map(\.count) == [1, 1])
    }
}
