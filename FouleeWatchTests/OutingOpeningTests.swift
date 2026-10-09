import Foundation
import Testing
@testable import FouleeWatch

/// How an outing opens at the wrist: fresh, or carrying on a walk the phone
/// handed over (issue #335).
@Suite("Outing opening")
struct OutingOpeningTests {
    private let now = Date(timeIntervalSince1970: 1_754_000_000)

    private func handoff(handedOverAt end: Date, distance: Double = 2_400) -> SessionHandoff {
        SessionHandoff(
            outingID: UUID(),
            phoneLeg: SessionHandoff.Leg(
                activity: .running,
                start: end.addingTimeInterval(-720),
                end: end,
                steps: 2_000,
                distanceMeters: distance,
                activeCalories: 180
            )
        )
    }

    @Test("Without a handoff the outing starts fresh, now")
    func fresh() {
        let opening = OutingOpening(continuing: nil, at: now)
        #expect(opening.leg.index == 0)
        #expect(opening.start == now)
        #expect(opening.priorLegs.isEmpty)
        #expect(opening.splitRecorder == SplitRecorder())
    }

    /// The two workouts touch: no gap and no overlap in Santé.
    @Test("A handoff carries on leg 1 of the same outing, from where the phone stopped")
    func continuing() throws {
        let handed = handoff(handedOverAt: now.addingTimeInterval(-5))
        let opening = OutingOpening(continuing: handed, at: now)

        #expect(opening.leg == handed.continuingLeg)
        #expect(opening.start == handed.handedOverAt)
        let phone = try #require(opening.priorLegs.first)
        #expect(opening.priorLegs.count == 1)
        #expect(phone.activity == .running)
        #expect(phone.start == handed.phoneLeg.start)
        #expect(phone.end == handed.handedOverAt)
        #expect(phone.steps == 2_000)
        #expect(phone.distanceMeters == 2_400)
    }

    /// A backdated start would claim minutes nobody measured.
    @Test("The watch leg never reaches further back than a handoff stays fresh")
    func theBackdateIsBounded() {
        let opening = OutingOpening(continuing: handoff(handedOverAt: now.addingTimeInterval(-600)), at: now)
        #expect(opening.start == now.addingTimeInterval(-SessionHandoff.freshness))
    }

    /// A phone clock a little ahead of the watch's must not open a leg that
    /// starts in the future.
    @Test("The watch leg never starts in the future")
    func neverInTheFuture() {
        let opening = OutingOpening(continuing: handoff(handedOverAt: now.addingTimeInterval(3)), at: now)
        #expect(opening.start == now)
    }

    /// 2.4 km on the phone: the 3rd kilometre is part phone, part wrist, so
    /// the first one timed is the 4th.
    @Test("Splits carry on past the phone's distance, untimed until a whole kilometre")
    func splitsCarryOn() {
        let handed = handoff(handedOverAt: now, distance: 2_400)
        var recorder = OutingOpening(continuing: handed, at: now).splitRecorder

        recorder.record(distanceMeters: 3_000, elapsed: 1_100)
        #expect(recorder.splits.isEmpty)

        recorder.record(distanceMeters: 4_000, elapsed: 1_400)
        #expect(recorder.splits == [WalkSplit(kilometre: 4, duration: 300)])
    }
}
