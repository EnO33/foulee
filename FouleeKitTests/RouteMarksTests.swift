import Foundation
import Testing
@testable import FouleeKit

@Suite("RouteMarks")
struct RouteMarksTests {
    /// A fix every 0.0001° (about 11 m), `steps` of them from `start`.
    private func line(from start: Coordinate, steps: Int, north: Double, east: Double) -> [Coordinate] {
        (0...steps).map {
            Coordinate(latitude: start.latitude + Double($0) * north, longitude: start.longitude + Double($0) * east)
        }
    }

    private let bordeaux = Coordinate(latitude: 44.84, longitude: -0.58)

    @Test("A pastille at each whole kilometre, an arrow halfway between")
    func kilometresAndArrows() {
        // About 3.3 km due north.
        let path = line(from: bordeaux, steps: 300, north: 0.0001, east: 0)
        let kilometres = RouteMarks.kilometres(along: [path])
        #expect(kilometres.count == 3)
        // One kilometre north is about 0.009° of latitude.
        #expect(abs(kilometres[0].coordinate.latitude - (bordeaux.latitude + 0.009)) < 0.0002)
        #expect(abs(kilometres[2].coordinate.latitude - (bordeaux.latitude + 0.027)) < 0.0005)
        // 500 m, 1.5 km, 2.5 km: 3.5 km is past the end.
        let arrows = RouteMarks.arrows(along: [path])
        #expect(arrows.count == 3)
        #expect(arrows[0].coordinate.latitude < kilometres[0].coordinate.latitude)
    }

    @Test("The arrows point the way the route runs")
    func bearings() {
        let north = line(from: bordeaux, steps: 100, north: 0.0001, east: 0)
        let south = Array(north.reversed())
        let east = line(from: Coordinate(latitude: 0, longitude: 0), steps: 100, north: 0, east: 0.0001)
        #expect(abs(RouteMarks.arrows(along: [north])[0].bearing - 0) < 1)
        #expect(abs(RouteMarks.arrows(along: [south])[0].bearing - 180) < 1)
        #expect(abs(RouteMarks.arrows(along: [east])[0].bearing - 90) < 1)
    }

    @Test("A gap between two legs adds no distance")
    func gapAddsNothing() {
        // Two legs of about 670 m each, far apart: the first kilometre falls
        // about 330 m into the second, never in the gap.
        let first = line(from: bordeaux, steps: 60, north: 0.0001, east: 0)
        let second = line(from: Coordinate(latitude: 45.5, longitude: 1.2), steps: 60, north: 0.0001, east: 0)
        let kilometres = RouteMarks.kilometres(along: [first, second])
        #expect(kilometres.count == 1)
        #expect(kilometres[0].coordinate.longitude == 1.2)
        #expect(kilometres[0].coordinate.latitude > 45.5)
    }

    @Test("No route, or one too short, has no mark")
    func shortRoutes() {
        #expect(RouteMarks.kilometres(along: []).isEmpty)
        #expect(RouteMarks.kilometres(along: [[bordeaux]]).isEmpty)
        let short = line(from: bordeaux, steps: 40, north: 0.0001, east: 0) // about 450 m
        #expect(RouteMarks.kilometres(along: [short]).isEmpty)
        #expect(RouteMarks.arrows(along: [short]).isEmpty)
    }
}
