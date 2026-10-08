import Foundation
import Testing
@testable import Foulee

/// The outing seen sport by sport (issue #318). The view only draws what these
/// decide, so the decisions are pinned here.
@Suite("Outing breakdown")
struct OutingBreakdownTests {
    private static let anchor = Date(timeIntervalSince1970: 1_716_768_000)

    private func leg(_ activity: RecordedActivity, from minute: Double, lasting minutes: Double, km: Double) -> WorkoutSummary {
        let start = Self.anchor.addingTimeInterval(minute * 60)
        return WorkoutSummary(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            durationSeconds: minutes * 60,
            distanceKm: km,
            activeCalories: 0,
            sourceName: "Foulée",
            activity: activity
        )
    }

    private func outing(_ legs: [WorkoutSummary]) -> WorkoutSummary {
        var row = legs[0]
        row.legs = legs
        return row
    }

    /// Walk → run → walk: two walks fold into one share, in first-done order.
    @Test("Each sport is one share, summed over its legs, in the order first done")
    func sharesBySport() {
        let row = outing([
            leg(.walking, from: 0, lasting: 10, km: 0.9),
            leg(.running, from: 10, lasting: 8, km: 1.5),
            leg(.walking, from: 18, lasting: 5, km: 0.45)
        ])

        let shares = OutingBreakdown.shares(of: row)

        #expect(shares.map(\.activity) == [.walking, .running])
        #expect(shares[0].duration == 15 * 60)
        #expect(abs(shares[0].distanceKm - 1.35) < 0.000_1)
        // 8 minutes over 1,5 km.
        #expect(shares[1].paceText == "5'20\"/km")
    }

    /// The hero already states a single sport's totals; repeating them is noise.
    @Test("A single session, or one sport only, has no breakdown")
    func singleSportHasNone() {
        let walk = leg(.walking, from: 0, lasting: 30, km: 2.5)
        #expect(OutingBreakdown.shares(of: walk).isEmpty)
        #expect(OutingBreakdown.shares(of: outing([walk, leg(.walking, from: 30, lasting: 5, km: 0.4)])).isEmpty)
    }

    /// The timeline is colour and length only: VoiceOver gets this or nothing.
    @Test("The timeline reads leg by leg, in French")
    func timelineSentence() {
        let text = OutingBreakdown.timelineDescription(of: [
            leg(.walking, from: 0, lasting: 10, km: 0.9),
            leg(.running, from: 10, lasting: 1, km: 0.2),
            leg(.walking, from: 11, lasting: 0.2, km: 0.01)
        ])
        // A twelve-second leg still reads as a minute rather than « 0 minute ».
        #expect(text == "Marche, 10 minutes ; course, 1 minute ; marche, 1 minute")
    }

    /// Walk and run must be told apart without relying on red against green.
    @Test("Walking and running are drawn in distinct colours")
    func distinctTints() {
        let tints = RecordedActivity.allCases.map(\.tint)
        #expect(Set(tints.map(\.description)).count == tints.count)
        #expect(RecordedActivity.walking.tint == ActivityPalette.walk)
        #expect(RecordedActivity.running.tint == ActivityPalette.run)
    }
}
