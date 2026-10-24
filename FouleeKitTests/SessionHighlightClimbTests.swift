import Foundation
import Testing
@testable import FouleeKit

/// The climb as a highlight of every outing, not of the hike alone
/// (issue #527): its own file, on the fixtures of the suite.
extension SessionHighlightTests {
    // MARK: - Climb

    /// The climb counts for every sport, not only the hike.
    @Test("A hillier walk than any of six months is a record")
    func hilliestWalk() {
        let records = records(longestKm: 20, climbing: 4, highestClimb: 120, averageClimb: 60)
        let highlight = SessionHighlight.pick(for: benchmark(outing(elevation: 180), records: records))
        #expect(highlight == SessionHighlight(
            angle: .record,
            title: "Ta marche la plus vallonnée depuis 6 mois",
            body: "180 m de dénivelé aujourd'hui. Le précédent record : 120 m."
        ))
    }

    /// A source that writes no climb says 0: no record to beat.
    @Test("Without three earlier outings that recorded a climb, no climb record")
    func noClimbHistory() {
        let records = records(climbing: 2, highestClimb: 40, averageClimb: 30)
        #expect(SessionHighlight.pick(for: benchmark(outing(elevation: 180), records: records)).angle != .record)
    }

    @Test("A quarter more climb than usual is worth saying, a flat outing is not")
    func climbAboveUsual() {
        let usual = records(climbing: 5, highestClimb: 300, averageClimb: 120)
        #expect(SessionHighlight.pick(for: benchmark(outing(elevation: 160), records: usual)) == SessionHighlight(
            angle: .climb,
            title: "Plus de dénivelé que d'habitude",
            body: "160 m de dénivelé, contre 120 m en moyenne ces 6 derniers mois."
        ))
        let flatHistory = records(climbing: 5, highestClimb: 30, averageClimb: 10)
        #expect(SessionHighlight.pick(for: benchmark(outing(elevation: 25), records: flatHistory)).angle == .arrival)
    }

    @Test("A month that already climbed more than the one before")
    func monthClimb() {
        let highlight = SessionHighlight.pick(for: benchmark(outing(), volume: volume(climb: 850, climbLastMonth: 620)))
        #expect(highlight == SessionHighlight(
            angle: .climb,
            title: "Ton mois grimpe plus que le précédent",
            body: "850 m de dénivelé depuis le 1er, contre 620 m en septembre."
        ))
    }

    @Test("Its climb is part of the outing's own figures")
    func arrivalWithClimb() {
        #expect(SessionHighlight.pick(for: benchmark(outing(km: 5.2, minutes: 48, elevation: 120))).body
            == "5,2 km en 48 min, 120 m de dénivelé. Le détail t'attend.")
    }
}
