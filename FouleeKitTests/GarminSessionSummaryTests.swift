import Foundation
import Testing
@testable import FouleeKit

/// The keys below are the contract with
/// `FouleeConnectIQ/source/SessionMessage.mc`.
@Suite("Garmin session summary")
struct GarminSessionSummaryTests {
    private static func message(_ overrides: [String: Any] = [:]) -> [String: Any] {
        [
            "t": "summary",
            "v": 1,
            "sport": "running",
            "start": 1_760_961_600,
            "end": 1_760_963_700,
            "duration": 1_800,
            "distanceM": 2_400,
            "ascentM": 120,
            "descentM": 115,
            "steps": 3_100,
        ].merging(overrides) { _, new in new }
    }

    @Test("The whole summary is read, typed")
    func fullMessage() throws {
        let summary = try #require(GarminSessionSummary.decode(Self.message()))
        #expect(summary.activity == .running)
        #expect(summary.startedAt == Date(timeIntervalSince1970: 1_760_961_600))
        #expect(summary.endedAt == Date(timeIntervalSince1970: 1_760_963_700))
        #expect(summary.durationSeconds == 1_800)
        #expect(summary.distanceMeters == 2_400)
        #expect(summary.ascentMeters == 120)
        #expect(summary.descentMeters == 115)
        #expect(summary.steps == 3_100)
    }

    @Test("A watch on an older build sends no climb: 0, the outing kept")
    func withoutAscent() throws {
        var message = Self.message()
        message["ascentM"] = nil
        #expect(try #require(GarminSessionSummary.decode(message)).ascentMeters == 0)
        #expect(try #require(GarminSessionSummary.decode(Self.message(["ascentM": -5]))).ascentMeters == 0)
    }

    @Test("A watch on an older build sends no descent: 0, the outing kept")
    func withoutDescent() throws {
        var message = Self.message()
        message["descentM"] = nil
        #expect(try #require(GarminSessionSummary.decode(message)).descentMeters == 0)
        #expect(try #require(GarminSessionSummary.decode(Self.message(["descentM": -5]))).descentMeters == 0)
    }

    @Test("Another type, another version or no clock is refused whole")
    func refused() {
        #expect(GarminSessionSummary.decode(Self.message(["t": "snapshot"])) == nil)
        #expect(GarminSessionSummary.decode(Self.message(["v": 2])) == nil)
        #expect(GarminSessionSummary.decode(Self.message(["start": 0])) == nil)
        #expect(GarminSessionSummary.decode(Self.message(["end": 1_760_961_000])) == nil)
        #expect(GarminSessionSummary.decode("summary") == nil)
    }

    @Test("Fields fall back instead of failing")
    func lenientFields() throws {
        let summary = try #require(GarminSessionSummary.decode(Self.message([
            "sport": "swimming", "steps": "3100", "distanceM": -5, "duration": 99_999,
        ])))
        #expect(summary.activity == .walking)
        #expect(summary.steps == 0)
        #expect(summary.distanceMeters == 0)
        #expect(summary.durationSeconds == 2_100)
    }

    @Test("The route is read in degrees, from the watch's fixed point")
    func route() throws {
        let summary = try #require(GarminSessionSummary.decode(Self.message([
            "route": [4_884_000, 235_000, 4_884_100, 235_050],
        ])))
        #expect(summary.route == [
            Coordinate(latitude: 48.84, longitude: 2.35),
            Coordinate(latitude: 48.841, longitude: 2.3505),
        ])
    }

    @Test("A malformed route costs the map, never the outing")
    func malformedRoute() throws {
        for route in [[4_884_000], [4_884_000, "east"] as [Any], [95_000_000, 0], "route"] as [Any] {
            let summary = try #require(GarminSessionSummary.decode(Self.message(["route": route])))
            #expect(summary.route.isEmpty)
        }
        #expect(try #require(GarminSessionSummary.decode(Self.message())).route.isEmpty)
    }

    @Test("A summary stored before routes existed still reads back")
    func storedWithoutRoute() throws {
        let stored = Data("""
        {"activity":"walking","startedAt":0,"endedAt":1800,"durationSeconds":1800,"distanceMeters":2400,"steps":3100}
        """.utf8)
        let summary = try JSONDecoder().decode(GarminSessionSummary.self, from: stored)
        #expect(summary.steps == 3_100)
        #expect(summary.ascentMeters == 0)
        #expect(summary.descentMeters == 0)
        #expect(summary.route.isEmpty)
    }
}
