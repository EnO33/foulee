import Foundation
import Testing
@testable import FouleeKit

@Suite("Garmin pending outings")
struct GarminPendingOutingsTests {
    private static let noon = Date(timeIntervalSince1970: 1_760_961_600)

    private static func outing(at start: Date, minutes: Double = 30) -> GarminSessionSummary {
        GarminSessionSummary(
            activity: .walking,
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            durationSeconds: minutes * 60,
            distanceMeters: 2_400,
            ascentMeters: 85,
            descentMeters: 80,
            steps: 3_100
        )
    }

    @Test("The same outing delivered twice is kept once, oldest first")
    func adding() {
        let early = Self.outing(at: Self.noon)
        let late = Self.outing(at: Self.noon.addingTimeInterval(3_600))
        let pending = GarminPendingOutings.adding(early, to: GarminPendingOutings.adding(late, to: []))
        #expect(GarminPendingOutings.adding(early, to: pending) == [early, late])
    }

    @Test("An outing goes once a Santé workout overlaps it")
    func coveredBySante() {
        let outing = Self.outing(at: Self.noon)
        let garminConnect = ActiveMinutes.WorkoutInterval(start: Self.noon.addingTimeInterval(20), duration: 1_790)
        let earlier = ActiveMinutes.WorkoutInterval(start: Self.noon.addingTimeInterval(-3_600), duration: 3_600)
        let now = Self.noon.addingTimeInterval(7_200)

        #expect(GarminPendingOutings.remaining([outing], healthKitWorkouts: [earlier], now: now) == [outing])
        #expect(GarminPendingOutings.remaining([outing], healthKitWorkouts: [garminConnect], now: now).isEmpty)
    }

    @Test("Past the streak's reach, or covering no clock, an outing goes")
    func expired() {
        let outing = Self.outing(at: Self.noon)
        let later = Self.noon.addingTimeInterval(GarminPendingOutings.horizon)
        #expect(GarminPendingOutings.remaining([outing], healthKitWorkouts: [], now: later).isEmpty)
        let empty = Self.outing(at: Self.noon, minutes: 0)
        #expect(GarminPendingOutings.remaining([empty], healthKitWorkouts: [], now: Self.noon).isEmpty)
    }

    @Test("Only the outings starting in the window count for it")
    func intervalsInWindow() {
        let inside = Self.outing(at: Self.noon)
        let before = Self.outing(at: Self.noon.addingTimeInterval(-86_400))
        let window = Self.noon.addingTimeInterval(-3_600)..<Self.noon.addingTimeInterval(3_600)
        #expect(GarminPendingOutings.intervals([before, inside], startingIn: window) == [inside.interval])
    }

    @Test("A pending outing of the window is a résumé row, under the watch's name")
    func workoutsInWindow() throws {
        let inside = Self.outing(at: Self.noon)
        let before = Self.outing(at: Self.noon.addingTimeInterval(-86_400))
        let window = Self.noon.addingTimeInterval(-3_600)..<Self.noon.addingTimeInterval(3_600)

        let rows = GarminPendingOutings.workouts([before, inside], startingIn: window)
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.startedAt == inside.startedAt && row.endedAt == inside.endedAt)
        #expect(row.durationSeconds == inside.durationSeconds)
        #expect(row.distanceKm == 2.4 && row.steps == 3_100)
        #expect(row.elevationMeters == 85)
        #expect(row.descentMeters == 80)
        #expect(row.activity == .walking)
        #expect(GarminPendingOutings.isPending(row))
        #expect(row.caloriesText == "— kcal")
    }

    @Test("A row keeps its identity from one read to the next, and differs from another outing's")
    func stableIdentity() {
        let window = Self.noon..<Self.noon.addingTimeInterval(7_200)
        let first = GarminPendingOutings.workouts([Self.outing(at: Self.noon)], startingIn: window)
        let again = GarminPendingOutings.workouts([Self.outing(at: Self.noon)], startingIn: window)
        let other = GarminPendingOutings.workouts([Self.outing(at: Self.noon.addingTimeInterval(60))], startingIn: window)
        #expect(first.map(\.id) == again.map(\.id))
        #expect(first.map(\.id) != other.map(\.id))
    }

    @Test("The detail of a pending outing draws the route the watch sent")
    func routeOfPendingOuting() throws {
        let walk = [Coordinate(latitude: 48.84, longitude: 2.35), Coordinate(latitude: 48.841, longitude: 2.35)]
        var outing = Self.outing(at: Self.noon)
        outing.route = walk
        let window = Self.noon..<Self.noon.addingTimeInterval(3_600)
        let row = try #require(GarminPendingOutings.workouts([outing], startingIn: window).first)

        let segments = GarminPendingOutings.route(of: row, in: [outing])
        #expect(segments.map(\.coordinates) == [walk])
        #expect(segments.map(\.id) == [row.id])

        var healthRow = row
        healthRow.sourceName = "Connect"
        #expect(GarminPendingOutings.route(of: healthRow, in: [outing]).isEmpty)
        outing.route = Array(walk.prefix(1))
        #expect(GarminPendingOutings.route(of: row, in: [outing]).isEmpty)
    }
}
