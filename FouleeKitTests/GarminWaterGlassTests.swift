import Foundation
import Testing
@testable import FouleeKit

/// The keys below are the contract with
/// `FouleeConnectIQ/source/WaterMessage.mc`.
@Suite("Garmin water glass")
struct GarminWaterGlassTests {
    private static func message(_ overrides: [String: Any] = [:]) -> [String: Any] {
        [
            "t": "water",
            "v": 1,
            "id": "1760961600-42",
            "at": 1_760_961_600,
            "ml": 250,
        ].merging(overrides) { _, new in new }
    }

    @Test("The glass is read whole, and known to Santé by its id")
    func fullMessage() throws {
        let glass = try #require(GarminWaterGlass.decode(Self.message()))
        #expect(glass.id == "1760961600-42")
        #expect(glass.loggedAt == Date(timeIntervalSince1970: 1_760_961_600))
        #expect(glass.milliliters == 250)
        #expect(glass.syncIdentifier == "garmin.water.1760961600-42")
    }

    @Test("Another type, another version, or no id, date or volume is refused whole")
    func refused() {
        #expect(GarminWaterGlass.decode(Self.message(["t": "summary"])) == nil)
        #expect(GarminWaterGlass.decode(Self.message(["v": 2])) == nil)
        #expect(GarminWaterGlass.decode(Self.message(["id": ""])) == nil)
        #expect(GarminWaterGlass.decode(Self.message(["id": 42])) == nil)
        #expect(GarminWaterGlass.decode(Self.message(["at": 0])) == nil)
        #expect(GarminWaterGlass.decode(Self.message(["ml": 0])) == nil)
        #expect(GarminWaterGlass.decode(Self.message(["ml": "250"])) == nil)
        #expect(GarminWaterGlass.decode("water") == nil)
    }

    @Test("A volume past any serving is a bug, not a drink")
    func implausibleVolume() {
        #expect(GarminWaterGlass.decode(Self.message(["ml": 2_000])) != nil)
        #expect(GarminWaterGlass.decode(Self.message(["ml": 2_001])) == nil)
    }

    @Test("The same glass delivered twice waits once")
    func adding() {
        let glass = GarminWaterGlass(id: "a", loggedAt: .now, milliliters: 250)
        let other = GarminWaterGlass(id: "b", loggedAt: .now, milliliters: 250)
        let pending = GarminWaterGlass.adding(other, to: GarminWaterGlass.adding(glass, to: []))
        #expect(GarminWaterGlass.adding(glass, to: pending) == [glass, other])
    }
}
