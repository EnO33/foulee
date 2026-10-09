import Foundation
import SwiftUI
import Testing
@testable import Foulee

/// The route a mirrored outing carries to the phone (issue #334).
///
/// Part of the wire format between two apps that update separately, so it is
/// held to the snapshot's own rule: degrade, never fail the decode.
@Suite("Mirrored route")
struct MirroredRouteTests {
    private let base = Date(timeIntervalSince1970: 1_754_000_000)

    private let run = MirroredRoutePortion(
        activity: .running,
        coordinates: [
            Coordinate(latitude: 48.86341, longitude: 2.32702),
            Coordinate(latitude: 48.86385, longitude: 2.32851)
        ]
    )

    private func snapshot(route: [MirroredRoutePortion]) -> WatchSessionSnapshot {
        WatchSessionSnapshot(
            sentAt: base,
            outingStartedAt: base.addingTimeInterval(-600),
            activity: .running,
            steps: 2_480,
            distanceMeters: 1_830,
            activeCalories: 108,
            heartRate: 118,
            isEnded: false,
            route: route
        )
    }

    // MARK: - Wire format

    @Test("A route survives the round trip inside its snapshot")
    func roundTrip() throws {
        let original = snapshot(route: [run])
        let decoded = try JSONDecoder().decode(
            WatchSessionSnapshot.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded == original)
    }

    /// It is resent whole every few seconds: half the bytes of
    /// `{"latitude":…,"longitude":…}` objects, for as long as the outing lasts.
    @Test("Points travel as one flat array of numbers")
    func pointsAreFlat() throws {
        let json = try #require(String(data: JSONEncoder().encode(run), encoding: .utf8))
        #expect(json.contains(#""points":[48.86341,2.32702,48.86385,2.32851]"#))
        #expect(!json.contains("latitude"))
    }

    @Test("Coordinates are rounded to about a metre")
    func coordinatesAreRounded() throws {
        let precise = MirroredRoutePortion(
            activity: .walking,
            coordinates: [Coordinate(latitude: 48.863_412_345, longitude: 2.327_018_765)]
        )
        let decoded = try JSONDecoder().decode(
            MirroredRoutePortion.self,
            from: JSONEncoder().encode(precise)
        )
        #expect(decoded.coordinates == [Coordinate(latitude: 48.86341, longitude: 2.32702)])
    }

    /// A watch on an older build sends no route: the figures still show.
    @Test("A snapshot without a route decodes with an empty one")
    func noRouteIsEmpty() throws {
        let json = #"{"sentAt": 0, "outingStartedAt": 0, "activity": "walking", "steps": 12}"#
        let decoded = try JSONDecoder().decode(WatchSessionSnapshot.self, from: Data(json.utf8))
        #expect(decoded.route.isEmpty)
        #expect(decoded.steps == 12)
    }

    @Test("A malformed route costs the map, never the figures")
    func aBadRouteKeepsTheFigures() throws {
        let json = #"{"sentAt": 0, "outingStartedAt": 0, "activity": "walking", "steps": 12, "route": "oops"}"#
        let decoded = try JSONDecoder().decode(WatchSessionSnapshot.self, from: Data(json.utf8))
        #expect(decoded.route.isEmpty)
        #expect(decoded.steps == 12)
    }

    @Test("An unknown sport still draws, as a walk")
    func anUnknownSportStillDraws() throws {
        let json = #"{"activity": "natation", "points": [48.8, 2.3, 48.9, 2.4]}"#
        let decoded = try JSONDecoder().decode(MirroredRoutePortion.self, from: Data(json.utf8))
        #expect(decoded.activity == .walking)
        #expect(decoded.coordinates.count == 2)
    }

    @Test("A dangling value is dropped, not fatal")
    func anOddValueIsDropped() throws {
        let json = #"{"activity": "running", "points": [48.8, 2.3, 48.9]}"#
        let decoded = try JSONDecoder().decode(MirroredRoutePortion.self, from: Data(json.utf8))
        #expect(decoded.coordinates == [Coordinate(latitude: 48.8, longitude: 2.3)])
    }

    // MARK: - Drawing

    @Test("A map is offered only once there is a line to draw")
    func drawableNeedsTwoPoints() {
        #expect(![MirroredRoutePortion]().isDrawable)
        #expect(![MirroredRoutePortion(activity: .walking, coordinates: [run.coordinates[0]])].isDrawable)
        #expect([run].isDrawable)
    }

    @Test("Each portion is drawn in its sport's colour")
    func strokesFollowTheSport() {
        let walk = MirroredRoutePortion(activity: .walking, coordinates: run.coordinates)
        let strokes = MirroredRoutePortion.strokes([walk, run])
        #expect(strokes.map(\.tint) == [SessionActivity.walking.tint, SessionActivity.running.tint])
        #expect(strokes.map(\.coordinates.count) == [2, 2])
    }

    /// The route is resent whole at every wake: a stroke whose identity changed
    /// each time would be torn down and redrawn instead of growing.
    @Test("A stroke keeps its identity from one wake to the next")
    func strokeIdentityIsStable() {
        let first = MirroredRoutePortion.strokes([run, run]).map(\.id)
        let second = MirroredRoutePortion.strokes([run, run, run]).map(\.id)
        #expect(Array(second.prefix(2)) == first)
        #expect(Set(second).count == 3)
        #expect(MirroredRoutePortion.strokeID(at: 0) != MirroredRoutePortion.strokeID(at: 256))
    }
}
