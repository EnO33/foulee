import CoreLocation
import Testing
@testable import FouleeWatch

/// What the wrist sends the phone of its route (issue #334): the « Plan »
/// page's portions, thinned to a phone map's needs.
@Suite("Mirrored route thinning")
struct MirroredRouteThinningTests {
    /// Points `metres` apart heading north from Paris — 1° of latitude is about
    /// 111 km, so the spacing is exact enough to test thresholds against.
    private func line(count: Int, metres: Double) -> [CLLocationCoordinate2D] {
        (0..<count).map {
            CLLocationCoordinate2D(latitude: 48.85 + Double($0) * metres / 111_195, longitude: 2.35)
        }
    }

    @Test("Points closer than the spacing are dropped")
    func closePointsAreDropped() {
        // A fix every 2 m over 100 m, thinned to about one every ten (just
        // under, so floating-point distance cannot flip the count).
        let thinned = MirroredRoutePortion.thinned(line(count: 51, metres: 2), spacing: 9)
        #expect(thinned.count == 11)
    }

    @Test("The first and the last point are always kept")
    func endsAreKept() {
        let points = line(count: 4, metres: 2)
        let thinned = MirroredRoutePortion.thinned(points, spacing: 10)
        // The last point is where the wearer is: never thinned away.
        #expect(thinned.first?.latitude == points.first?.latitude)
        #expect(thinned.last?.latitude == points.last?.latitude)
        #expect(thinned.count == 2)
    }

    @Test("A single fix stays a single fix, and nothing stays nothing")
    func degenerateRoutes() {
        #expect(MirroredRoutePortion.thinned(line(count: 1, metres: 0), spacing: 10).count == 1)
        #expect(MirroredRoutePortion.thinned([], spacing: 10).isEmpty)
    }

    @Test("However long the outing, the route stays under its ceiling")
    func aLongOutingIsCapped() {
        // 40 km with a fix every 5 m: 8 000 fixes, far past the ceiling.
        let portion = WatchRoutePortion(id: UUID(), activity: .running, coordinates: line(count: 8_000, metres: 5))
        let mirrored = MirroredRoutePortion.mirrored([portion])
        let points = mirrored.reduce(0) { $0 + $1.coordinates.count }
        #expect(points <= MirroredRoutePortion.maximumPoints + 1)
        #expect(points > MirroredRoutePortion.maximumPoints / 2)
    }

    @Test("Each portion keeps its sport, and junctions still meet")
    func portionsKeepTheirSportAndJunctions() {
        let walk = line(count: 30, metres: 5)
        let run = [walk[walk.count - 1]] + line(count: 30, metres: 5).map {
            CLLocationCoordinate2D(latitude: $0.latitude + 0.002, longitude: $0.longitude)
        }
        let mirrored = MirroredRoutePortion.mirrored([
            WatchRoutePortion(id: UUID(), activity: .walking, coordinates: walk),
            WatchRoutePortion(id: UUID(), activity: .running, coordinates: run)
        ])
        #expect(mirrored.map(\.activity) == [.walking, .running])
        #expect(mirrored[0].coordinates.last == mirrored[1].coordinates.first)
    }
}
