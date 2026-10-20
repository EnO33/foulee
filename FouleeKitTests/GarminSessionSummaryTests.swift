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
        #expect(summary.steps == 3_100)
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
}
