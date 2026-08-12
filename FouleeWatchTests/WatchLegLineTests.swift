import Foundation
import Testing
@testable import FouleeWatch

/// How a leg words itself on the « Jambes » page (issue #276).
///
/// Nothing new is measured here — a leg already carries its distance and its
/// two dates, and the pace is the division of one by the other. What is worth
/// pinning is the wording, and the two cases where the honest answer is to say
/// less: a leg too short to divide, and a leg still running.
@Suite("Leg line and pace")
struct WatchLegLineTests {
    private let base = Date(timeIntervalSince1970: 1_754_000_000)

    private func segment(
        from: TimeInterval,
        to: TimeInterval?,
        metres: Double
    ) -> WatchWorkoutSegment {
        WatchWorkoutSegment(
            id: UUID(),
            activity: .walking,
            start: base.addingTimeInterval(from),
            end: to.map { base.addingTimeInterval($0) },
            steps: 0,
            distanceMeters: metres,
            activeCalories: 0
        )
    }

    // MARK: - Pace

    @Test("Ten minutes over a kilometre and a half reads as 6'40\"/km")
    func paceDivides() {
        #expect(TimeInterval(600).paceText(overKm: 1.5) == "6'40\"/km")
    }

    @Test("A pace is stated to the second, not rounded to the minute")
    func paceKeepsSeconds() {
        // 457.8 s/km — the seeded run leg.
        #expect(TimeInterval(380).paceText(overKm: 0.83) == "7'37\"/km")
    }

    /// A leg can be as short as 15 s (`WatchWorkoutStore.minimumLegDuration`).
    /// Dividing twenty paces of a GPS-less distance estimate produces a figure
    /// that looks precise and is not, so below 50 m there is no pace to state.
    @Test("Under fifty metres there is no pace to state", arguments: [0.0, 0.01, 0.049])
    func noPaceUnderFiftyMetres(km: Double) {
        #expect(TimeInterval(15).paceText(overKm: km) == nil)
    }

    @Test("A duration of zero has no pace either")
    func noPaceWithoutTime() {
        #expect(TimeInterval(0).paceText(overKm: 1) == nil)
    }

    /// Not a pace — a pause somebody forgot to end.
    @Test("An absurdly slow pace is withheld rather than printed")
    func absurdPaceIsWithheld() {
        #expect(TimeInterval(99 * 60) .paceText(overKm: 1) == nil)
        #expect(TimeInterval(99 * 60 - 1).paceText(overKm: 1) != nil)
    }

    // MARK: - The line

    @Test("A closed leg states its duration, its distance, its pace and its cadence")
    func closedLegReadsInFull() {
        var leg = segment(from: 0, to: 724, metres: 1_000)
        leg.steps = 1_435
        #expect(
            leg.lineText(at: base.addingTimeInterval(9_999))
                == "12:04 · 1,0 km · 12'04\"/km · 120\u{00A0}pas/min"
        )
    }

    /// The whole reason `lineText` is a function. A stored property would have
    /// frozen the running leg at whatever second it was first drawn — the
    /// defect issue #266 fixed on the session clock.
    @Test("The leg in flight grows with the clock it is read at")
    func runningLegGrows() {
        let leg = segment(from: 0, to: nil, metres: 1_000)
        #expect(leg.lineText(at: base.addingTimeInterval(60)).hasPrefix("01:00"))
        #expect(leg.lineText(at: base.addingTimeInterval(120)).hasPrefix("02:00"))
    }

    /// The line ends after the distance rather than printing a placeholder: a
    /// leg that has not gone far yet reads as exactly that, while « —'—"/km »
    /// reads as a broken counter.
    @Test("A leg too short to divide drops the pace instead of faking one")
    func shortLegDropsThePace() {
        let leg = segment(from: 0, to: 15, metres: 20)
        #expect(leg.lineText(at: base) == "00:15 · 0,0 km")
    }
}

/// Steps per minute (issue #302).
///
/// HealthKit has nothing to offer here — the only identifier carrying the word
/// is `cyclingCadence` — so dividing the step count is not a fallback but the
/// only road.
@Suite("Cadence")
struct CadenceTests {
    @Test("A brisk walk reads around a hundred and twenty")
    func aWalkReadsAsAWalk() {
        // 1 435 pas en 724 s — la jambe de marche de la graine.
        #expect(cadenceText(steps: 1_435, over: 724) == "120\u{00A0}pas/min")
    }

    @Test("A run reads around a hundred and sixty-five")
    func aRunReadsAsARun() {
        #expect(cadenceText(steps: 1_045, over: 380) == "165\u{00A0}pas/min")
    }

    /// Rounded to five: over a short stretch the step counter's own
    /// quantisation is worth a dozen or so steps a minute on its own, and a
    /// figure stated to the step would be showing that and calling it cadence.
    @Test("The figure is rounded to five", arguments: [
        (600, 300.0, "120\u{00A0}pas/min"),   // 120 exactly
        (611, 300.0, "120\u{00A0}pas/min"),   // 122,2 → 120
        (620, 300.0, "125\u{00A0}pas/min")    // 124 → 125
    ])
    func roundedToFive(steps: Int, elapsed: TimeInterval, expected: String) {
        #expect(cadenceText(steps: steps, over: elapsed) == expected)
    }

    /// Nothing under ten seconds, and nothing without steps. A leg in flight
    /// starts at zero of both.
    @Test("Too short or too still says nothing", arguments: [
        (100, 9.0),
        (0, 600.0),
        (0, 0.0)
    ])
    func nothingToDivide(steps: Int, elapsed: TimeInterval) {
        #expect(cadenceText(steps: steps, over: elapsed) == nil)
    }
}
