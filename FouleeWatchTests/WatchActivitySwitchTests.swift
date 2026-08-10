import Foundation
import Testing
@testable import FouleeWatch

/// The switching rule of issue #249, driven from hand-built sequences.
///
/// Every case here is one no wrist can be asked to produce on demand: an
/// estimate that asserts both walking and running, one that asserts nothing at
/// all, a device stamp from before the session started. `ActivitySwitchDetector`
/// is pure precisely so these are cheap to state — the alternative is going for
/// a run and hoping.
@Suite("Activity switch decision")
struct WatchActivitySwitchTests {
    private let start = Date(timeIntervalSince1970: 1_754_000_000)

    private func detector(
        startedAs: SessionActivity = .walking,
        confirmations: Int = 2
    ) -> ActivitySwitchDetector {
        ActivitySwitchDetector(startedAs: startedAs, at: start, confirmations: confirmations)
    }

    private func walk(at offset: TimeInterval) -> MotionActivityEstimate {
        motionEstimate(startDate: start.addingTimeInterval(offset), walking: true)
    }

    private func run(at offset: TimeInterval) -> MotionActivityEstimate {
        motionEstimate(startDate: start.addingTimeInterval(offset), running: true)
    }

    private func run(began: TimeInterval, seen: TimeInterval) -> MotionActivityEstimate {
        motionEstimate(
            startDate: start.addingTimeInterval(began),
            receivedAt: start.addingTimeInterval(seen),
            running: true
        )
    }

    private func walk(began: TimeInterval, seen: TimeInterval) -> MotionActivityEstimate {
        motionEstimate(
            startDate: start.addingTimeInterval(began),
            receivedAt: start.addingTimeInterval(seen),
            walking: true
        )
    }

    private func silence(at offset: TimeInterval) -> MotionActivityEstimate {
        motionEstimate(startDate: start.addingTimeInterval(offset))
    }

    // MARK: - What counts as evidence

    @Test("Only an unambiguous walk or run is evidence")
    func onlyOneFlagAtATimeCounts() {
        func reading(_ estimate: MotionActivityEstimate) -> MotionActivityReading {
            estimate.reading(minimumConfidence: .medium)
        }
        #expect(reading(walk(at: 0)) == .activity(.walking))
        #expect(reading(run(at: 0)) == .activity(.running))
        // The flags are not mutually exclusive. `if walking … else if running`
        // would answer « marche » here — silently preferring one of them at the
        // exact moment the device is least sure.
        #expect(reading(motionEstimate(startDate: start, walking: true, running: true)) == .noEvidence)
        // Both clear is a real, frequent reading, not an error — and it is
        // also what a stationary wearer, a bike ride, a car journey and an
        // unclassifiable estimate all look like from here, since Foulée records
        // none of them and stopped carrying their flags with issue #252.
        #expect(reading(silence(at: 0)) == .noEvidence)
    }

    @Test("Below the confidence threshold, a clear flag is still not evidence")
    func confidenceGatesEverything() {
        func reading(_ confidence: MotionActivityConfidence) -> MotionActivityReading {
            motionEstimate(startDate: start, confidence: confidence, running: true)
                .reading(minimumConfidence: .medium)
        }
        #expect(reading(.high) == .activity(.running))
        #expect(reading(.medium) == .activity(.running))
        #expect(reading(.low) == .noEvidence)
        // A level this app cannot name is not evidence either. The cost is
        // detection going quiet — which leaves the session exactly as it was
        // started — rather than a wrong segment saved to Santé for good.
        #expect(reading(.unrecognised) == .noEvidence)
    }

    // MARK: - When a switch is confirmed

    @Test("Two consecutive readings of the other activity switch the session")
    func twoConsecutiveReadingsSwitch() {
        var detector = detector()
        #expect(detector.observe(run(at: 60)) == nil)
        #expect(detector.observe(run(at: 90))?.activity == .running)
        #expect(detector.current == .running)
    }

    @Test("One aberrant estimate never moves the session")
    func oneReadingIsNotEnough() {
        var detector = detector()
        #expect(detector.observe(run(at: 60)) == nil)
        // The wearer was walking all along; the next reading says so.
        #expect(detector.observe(walk(at: 90)) == nil)
        #expect(detector.current == .walking)
    }

    @Test("A noisy sequence produces no switch at all")
    func noisySequenceIsInert() {
        var detector = detector()
        // Ten minutes of the device changing its mind every 30 s. A rule that
        // switched on any single disagreement would carve this walk into twenty
        // segments in Santé, permanently.
        for step in 1...20 {
            let offset = TimeInterval(step * 30)
            let estimate = step.isMultiple(of: 2) ? run(at: offset) : walk(at: offset)
            #expect(detector.observe(estimate) == nil)
        }
        #expect(detector.current == .walking)
    }

    @Test("Estimates that assert nothing neither confirm nor cancel")
    func silenceIsNeutral() {
        var detector = detector()
        #expect(detector.observe(run(at: 60)) == nil)
        // The device asserting nothing is not the device disagreeing. Treating
        // it as a cancellation would make a switch nearly impossible: silence is
        // common, and it lands between consecutive readings all the time.
        #expect(detector.observe(silence(at: 70)) == nil)
        #expect(detector.observe(run(at: 80))?.activity == .running)
    }

    @Test("A candidate with no support for a long time starts over")
    func staleCandidateRestarts() {
        var detector = detector()
        #expect(detector.observe(run(at: 60)) == nil)
        // 91 s later, past `staleAfter`. Without expiry, "two consecutive
        // readings" would happily pair an aberrant estimate with another one
        // minutes later — two moments that agree about nothing.
        #expect(detector.observe(run(at: 151)) == nil)
        #expect(detector.observe(run(at: 161))?.activity == .running)
    }

    @Test("Coming back to the starting activity needs its own two readings")
    func switchingBackIsNotFree() {
        var detector = detector()
        _ = detector.observe(run(at: 60))
        _ = detector.observe(run(at: 90))
        #expect(detector.current == .running)
        #expect(detector.observe(walk(at: 120)) == nil)
        #expect(detector.observe(walk(at: 150))?.activity == .walking)
        #expect(detector.current == .walking)
    }

    @Test("A session started as a run detects the walk, not the run")
    func theStartingActivityIsWhateverTheSessionOpenedAs() {
        var detector = detector(startedAs: .running)
        #expect(detector.current == .running)
        #expect(detector.observe(run(at: 60)) == nil)
        _ = detector.observe(walk(at: 90))
        #expect(detector.observe(walk(at: 120))?.activity == .walking)
    }

    @Test("The confirmation count is the knob, and it is load-bearing")
    func confirmationsIsNotDecorative() {
        var detector = detector(confirmations: 1)
        #expect(detector.observe(run(at: 60))?.activity == .running)
    }

    // MARK: - Where the boundary lands

    @Test("The boundary is where the device says the activity began")
    func switchIsDatedFromTheFirstEstimateOfTheStreak() {
        var detector = detector()
        // The measured shape of issue #248: CoreMotion hands over the run some
        // seconds after it started, and its own `startDate` says when.
        _ = detector.observe(run(began: 100, seen: 125))
        let switched = detector.observe(run(began: 100, seen: 155))
        // Not 155, and not 125 either: dating the segment from the confirming
        // estimate would stamp Santé with a boundary a full latency late, which
        // is the whole thing the device stamp exists to avoid.
        #expect(switched?.date == start.addingTimeInterval(100))
    }

    @Test("A boundary never precedes the session or the previous segment")
    func boundariesAreClamped() {
        var detector = detector()
        // Already running when « Démarrer » was pressed: the device's stamp for
        // the activity predates the session itself.
        _ = detector.observe(run(began: -600, seen: 10))
        #expect(detector.observe(run(began: -600, seen: 20))?.date == start)
        // And a walk whose stamp predates the run segment it follows. Segments
        // are consecutive by construction, so the only correct answer is the
        // previous boundary — never an overlap.
        _ = detector.observe(walk(began: -300, seen: 200))
        #expect(detector.observe(walk(began: -300, seen: 210))?.date == start)
    }

    @Test("A boundary never lands in the future")
    func aBoundaryNeverOutrunsTheReading() {
        var detector = detector()
        // A device clock slightly ahead of ours: the activity claims to have
        // begun after we were told about it.
        _ = detector.observe(run(began: 200, seen: 100))
        let switched = detector.observe(run(began: 200, seen: 130))
        #expect(switched?.date == start.addingTimeInterval(130))
    }
}
