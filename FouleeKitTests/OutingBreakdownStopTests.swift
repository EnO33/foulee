import Foundation
import Testing
@testable import FouleeKit

/// Cover for #553: the detail of a merged outing tells its stop apart from
/// its legs.
@Suite("Outing breakdown — stops")
struct OutingBreakdownStopTests {
    private static let anchor = Date(timeIntervalSince1970: 1_716_768_000)

    private func leg(_ activity: RecordedActivity, from minute: Double, lasting minutes: Double) -> WorkoutSummary {
        let start = Self.anchor.addingTimeInterval(minute * 60)
        return WorkoutSummary(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            durationSeconds: minutes * 60,
            distanceKm: minutes / 10,
            activeCalories: 0,
            sourceName: "Foulée",
            activity: activity
        )
    }

    @Test("The stop between two parts is read aloud between them")
    func stopIsRead() {
        let text = OutingBreakdown.timelineDescription(of: [
            leg(.walking, from: 0, lasting: 30),
            leg(.walking, from: 42, lasting: 20)
        ])
        #expect(text == "Marche, 30 minutes ; arrêt de 12 minutes ; marche, 20 minutes")
    }

    @Test("A leg is read in words: its hours, duration, distance and pace")
    func legIsSpoken() {
        let text = OutingBreakdown.legSpokenText(leg(.walking, from: 0, lasting: 15))
        #expect(text.hasPrefix("de "))
        #expect(text.hasSuffix(", 15 minutes, 1,50 km, 10 minutes par kilomètre"))
    }

    @Test("Legs that touch, or nearly, have no stop between them")
    func touchingLegsHaveNoStop() {
        let text = OutingBreakdown.timelineDescription(of: [
            leg(.walking, from: 0, lasting: 10),
            leg(.running, from: 10.5, lasting: 8)
        ])
        #expect(text == "Marche, 10 minutes ; course, 8 minutes")
    }

    @Test("Steps are counted leg by leg, never across the stop")
    func stepWindowsSkipTheStop() {
        let first = leg(.walking, from: 0, lasting: 30)
        let second = leg(.walking, from: 42, lasting: 20)
        var outing = first
        outing.endedAt = second.endedAt
        outing.legs = [first, second]

        #expect(OutingBreakdown.stepWindows(of: outing) == [
            DateInterval(start: first.startedAt, end: first.endedAt),
            DateInterval(start: second.startedAt, end: second.endedAt)
        ])
    }

    @Test("A single session is its own window")
    func singleSessionWindow() {
        let walk = leg(.walking, from: 0, lasting: 30)
        #expect(OutingBreakdown.stepWindows(of: walk) == [DateInterval(start: walk.startedAt, end: walk.endedAt)])
    }
}
