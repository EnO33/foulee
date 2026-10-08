import CoreLocation
import Testing
@testable import FouleeWatch

/// The route cut at the outing's legs, each in its sport (issue #320).
@Suite("Watch route portions")
struct WatchRoutePortionTests {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func fix(_ second: TimeInterval) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 48.85 + second / 100_000, longitude: 2.34),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: -1,
            timestamp: base.addingTimeInterval(second)
        )
    }

    private func leg(_ activity: SessionActivity, from start: TimeInterval, to end: TimeInterval?) -> WatchWorkoutSegment {
        WatchWorkoutSegment(
            id: UUID(),
            activity: activity,
            start: base.addingTimeInterval(start),
            end: end.map { base.addingTimeInterval($0) },
            steps: 0,
            distanceMeters: 0,
            activeCalories: 0
        )
    }

    private func latitudes(_ portion: WatchRoutePortion) -> [Double] {
        portion.coordinates.map(\.latitude)
    }

    @Test("Three legs give three portions, each in its sport, joined end to start")
    func threeLegs() {
        let legs = [leg(.walking, from: 0, to: 60), leg(.running, from: 60, to: 120), leg(.walking, from: 120, to: 180)]
        let fixes = stride(from: 0.0, through: 170, by: 10).map(fix)

        let portions = WatchRoutePortion.portions(of: fixes, legs: legs, current: nil)

        #expect(portions.map(\.activity) == [.walking, .running, .walking])
        #expect(portions.map(\.id) == legs.map(\.id))
        // Each portion after the first opens on the point the previous ended on.
        for (previous, next) in zip(portions, portions.dropFirst()) {
            #expect(latitudes(next).first == latitudes(previous).last)
        }
        // Every fix is drawn, and only the junctions twice.
        #expect(portions.map(\.coordinates.count).reduce(0, +) == fixes.count + 2)
    }

    /// A boundary instant opens the leg it starts.
    @Test("A fix exactly on a boundary starts the next portion")
    func boundaryFix() {
        let legs = [leg(.walking, from: 0, to: 60), leg(.running, from: 60, to: nil)]
        let portions = WatchRoutePortion.portions(of: [fix(0), fix(30), fix(60), fix(90)], legs: legs, current: nil)
        #expect(latitudes(portions[0]) == [fix(0), fix(30)].map(\.coordinate.latitude))
        #expect(latitudes(portions[1]) == [fix(30), fix(60), fix(90)].map(\.coordinate.latitude))
    }

    @Test("One leg is one portion")
    func singleLeg() {
        let portions = WatchRoutePortion.portions(of: [fix(0), fix(10)], legs: [leg(.running, from: 0, to: nil)], current: nil)
        #expect(portions.count == 1)
        #expect(portions.first?.activity == .running)
    }

    /// The screen renames the sport at once and records it later
    /// (`applySwitch`): the line in flight must say what the screen says.
    @Test("The leg in flight is drawn in the sport detected now")
    func inFlightFollowsDetection() {
        let legs = [leg(.walking, from: 0, to: nil)]
        let live = WatchRoutePortion.portions(of: [fix(0), fix(10)], legs: legs, current: .running)
        #expect(live.first?.activity == .running)
        // A closed leg keeps the sport it was recorded as.
        let closed = [leg(.walking, from: 0, to: 60)]
        #expect(WatchRoutePortion.portions(of: [fix(0), fix(10)], legs: closed, current: .running).first?.activity == .walking)
    }

    @Test("Nothing to draw without two points; no legs yet is one portion")
    func edges() {
        #expect(WatchRoutePortion.portions(of: [], legs: [leg(.walking, from: 0, to: nil)], current: nil).isEmpty)
        #expect(WatchRoutePortion.portions(of: [fix(0)], legs: [leg(.walking, from: 0, to: nil)], current: nil).isEmpty)
        let solo = WatchRoutePortion.portions(of: [fix(0), fix(10)], legs: [], current: .running)
        #expect(solo.count == 1)
        #expect(solo.first?.activity == .running)
    }

    @Test("Walk and run are drawn in the phone's colours")
    func sharedPalette() {
        #expect(SessionActivity.walking.tint == ActivityPalette.walk)
        #expect(SessionActivity.running.tint == ActivityPalette.run)
    }
}
