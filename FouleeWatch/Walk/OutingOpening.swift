import Foundation

/// How an outing opens on the wrist: from scratch, or carrying on a walk the
/// phone handed over (issue #335).
///
/// A value computed before anything is opened, so the one decision of a
/// handoff — which outing, which leg, from when, after what — is asserted
/// without a session.
struct OutingOpening: Equatable {
    /// The leg the wrist records first: 0 of a new outing, or the handed-over
    /// outing's next one.
    var leg: OutingLeg
    /// Where that leg begins.
    var start: Date
    /// Legs already recorded elsewhere — the phone's — counted in the outing's
    /// clock and totals, never saved again from here.
    var priorLegs: [WatchWorkoutSegment]

    init(continuing handoff: SessionHandoff?, at now: Date) {
        guard let handoff else {
            self.init(leg: OutingLeg(outingID: UUID(), index: 0), start: now, priorLegs: [])
            return
        }
        // The watch leg starts where the phone stopped, so the two touch. But
        // never further back than a handoff stays fresh — a backdated start
        // claims time the wrist did not measure — and never in the future.
        let earliest = now.addingTimeInterval(-SessionHandoff.freshness)
        let phone = handoff.phoneLeg
        self.init(
            leg: handoff.continuingLeg,
            start: min(max(handoff.handedOverAt, earliest), now),
            priorLegs: [
                WatchWorkoutSegment(
                    id: handoff.outingID,
                    activity: phone.activity,
                    start: phone.start,
                    end: phone.end,
                    steps: phone.steps,
                    distanceMeters: phone.distanceMeters,
                    activeCalories: phone.activeCalories
                )
            ]
        )
    }

    private init(leg: OutingLeg, start: Date, priorLegs: [WatchWorkoutSegment]) {
        self.leg = leg
        self.start = start
        self.priorLegs = priorLegs
    }
}

extension OutingOpening {
    /// The kilometre splits to start the outing with: fresh, or carrying on
    /// past the distance the phone already covered (issue #335).
    var splitRecorder: SplitRecorder {
        guard !priorLegs.isEmpty else { return SplitRecorder() }
        let covered = WatchActivityTotals.of(priorLegs, at: start)
        return SplitRecorder(continuingFrom: covered.distanceMeters, elapsed: covered.elapsed)
    }
}
