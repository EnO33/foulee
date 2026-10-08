import CoreGraphics
import Foundation
import Testing
@testable import Foulee

/// What the finger finds (issue #319): the leg at an instant, the nearest
/// heart-rate reading, and the line a tap landed on.
@Suite("Outing selection")
struct OutingSelectionTests {
    private static let anchor = Date(timeIntervalSince1970: 1_716_768_000)

    private func leg(_ activity: RecordedActivity, from minute: Double, lasting minutes: Double, km: Double = 1) -> WorkoutSummary {
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

    private func at(_ minute: Double) -> Date { Self.anchor.addingTimeInterval(minute * 60) }

    /// A boundary is the instant one leg ends and the next begins: it belongs
    /// to the one it starts, so the finger never finds two legs at once.
    @Test("The leg at an instant, boundaries going to the leg they start")
    func legAtInstant() {
        let legs = [leg(.walking, from: 0, lasting: 10), leg(.running, from: 10, lasting: 8)]
        #expect(OutingBreakdown.leg(at: at(5), in: legs)?.activity == .walking)
        #expect(OutingBreakdown.leg(at: at(10), in: legs)?.activity == .running)
        #expect(OutingBreakdown.leg(at: at(18), in: legs)?.activity == .running)
        #expect(OutingBreakdown.leg(at: at(19), in: legs) == nil)
        #expect(OutingBreakdown.leg(at: at(-1), in: legs) == nil)
    }

    @Test("A leg reads as times, distance and pace")
    func legLine() {
        let run = leg(.running, from: 10, lasting: 8, km: 1.5)
        let expected = "\(run.startedAt.clockText) → \(run.endedAt.clockText) · 1,50 km · 5'20\"/km"
        #expect(OutingBreakdown.legText(run) == expected)
    }

    @Test("The clock is French and 24-hour whatever the locale")
    func clockText() {
        var components = DateComponents()
        components.year = 2024
        components.month = 5
        components.day = 27
        components.hour = 20
        components.minute = 5
        let date = Calendar.current.date(from: components) ?? .now
        #expect(date.clockText == "20:05")
    }

    @Test("The nearest heart-rate reading, on either side")
    func nearestReading() {
        let readings = [0.0, 60, 120].map {
            HeartRateSample(id: UUID(), date: Self.anchor.addingTimeInterval($0), bpm: Int(100 + $0 / 6))
        }
        let detail = WorkoutDetail(summary: leg(.walking, from: 0, lasting: 2), heartRateSamples: readings, stepsCount: 0)
        #expect(detail.heartRate(nearest: Self.anchor.addingTimeInterval(-30))?.bpm == 100)
        #expect(detail.heartRate(nearest: Self.anchor.addingTimeInterval(29))?.bpm == 100)
        #expect(detail.heartRate(nearest: Self.anchor.addingTimeInterval(31))?.bpm == 110)
        #expect(detail.heartRate(nearest: Self.anchor.addingTimeInterval(500))?.bpm == 120)
        let empty = WorkoutDetail(summary: leg(.walking, from: 0, lasting: 2), heartRateSamples: [], stepsCount: 0)
        #expect(empty.heartRate(nearest: Self.anchor) == nil)
    }
}

@Suite("Route hit test")
struct RouteHitTestTests {
    private let horizontal = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
    private let lower = [CGPoint(x: 0, y: 40), CGPoint(x: 100, y: 40)]

    @Test("Distance to a segment: perpendicular inside, nearest end outside")
    func segmentDistance() {
        #expect(RouteHitTest.distance(from: CGPoint(x: 50, y: 10), to: horizontal) == 10)
        #expect(RouteHitTest.distance(from: CGPoint(x: 103, y: 4), to: horizontal) == 5)
        #expect(RouteHitTest.distance(from: CGPoint(x: 3, y: 4), to: [CGPoint.zero]) == 5)
        #expect(RouteHitTest.distance(from: .zero, to: []) == .infinity)
    }

    @Test("The nearest line within reach wins; a tap far from all of them picks none")
    func nearestLine() {
        #expect(RouteHitTest.nearestStroke(to: CGPoint(x: 50, y: 30), among: [horizontal, lower]) == 1)
        #expect(RouteHitTest.nearestStroke(to: CGPoint(x: 50, y: 8), among: [horizontal, lower]) == 0)
        #expect(RouteHitTest.nearestStroke(to: CGPoint(x: 50, y: 200), among: [horizontal, lower]) == nil)
    }

    /// A tap exactly between two legs goes to the earlier one, every time.
    @Test("A tie goes to the earlier leg")
    func tie() {
        #expect(RouteHitTest.nearestStroke(to: CGPoint(x: 50, y: 20), among: [horizontal, lower]) == 0)
    }
}
