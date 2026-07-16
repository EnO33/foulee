import Foundation
import Testing
@testable import Foulee

@Suite struct WaterGlassTests {
    @Test func defaultsWithoutSnapshot() {
        #expect(WaterGlass.milliliters(from: nil) == 250)
    }

    @Test func syncedGlassSizeWins() {
        var snapshot = WidgetSnapshot.placeholder
        snapshot.hydrationGlassML = 330
        #expect(WaterGlass.milliliters(from: snapshot) == 330)
    }

    /// A snapshot written by a build that predates `hydrationGlassML` must
    /// decode with the 250 ml default, not fail or blank the widget.
    @Test func oldSnapshotDecodesWithDefaultGlassSize() throws {
        let json = """
        {"steps":1,"stepsGoal":2,"minutes":3,"minutesGoal":4,"distanceKm":5,"calories":6,"streak":7}
        """
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.hydrationGlassML == 250)
        #expect(WaterGlass.milliliters(from: snapshot) == 250)
    }
}
