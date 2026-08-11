import CoreMotion
import Foundation
import Testing
@testable import Foulee

/// Cutting a finished session into walking and running (issue #246).
///
/// Every case here is one no pavement produces on demand: a history that starts
/// after the session did, an estimate asserting both flags at once, an outing
/// CoreMotion says nothing about. The reduction is pure precisely so they can
/// be stated rather than hoped for.
@Suite("Activity segmentation")
struct ActivitySegmentationTests {
    private let start = Date(timeIntervalSince1970: 1_754_000_000)

    private func at(_ offset: TimeInterval) -> Date { start.addingTimeInterval(offset) }

    private func sample(
        _ offset: TimeInterval,
        walking: Bool = false,
        running: Bool = false,
        confidence: MotionActivityConfidence = .high
    ) -> MotionHistorySample {
        MotionHistorySample(startDate: at(offset), confidence: confidence, walking: walking, running: running)
    }

    // MARK: - The whole session is covered, always

    @Test("A session nothing was recorded for is one walk, not nothing")
    func anEmptyHistoryStillCoversTheSession() {
        let segments = ActivitySegmentation.segments([], from: start, to: at(1_800))
        // Returning nothing would make « dominant » a verdict on an empty set,
        // and the session's own duration would vanish from issue #247's sums.
        #expect(segments == [ActivitySegment(activity: .walking, start: start, end: at(1_800))])
    }

    @Test("A history that starts late leaves no hole at the beginning")
    func aLateHistoryFillsTheGap() {
        let segments = ActivitySegmentation.segments(
            [sample(300, running: true)],
            from: start,
            to: at(900)
        )
        #expect(segments == [
            ActivitySegment(activity: .walking, start: start, end: at(300)),
            ActivitySegment(activity: .running, start: at(300), end: at(900))
        ])
    }

    @Test("Estimates from before the session are clipped, not counted")
    func earlierEstimatesAreClipped() {
        // The query returns whatever overlaps the window; an estimate that
        // began an hour earlier still describes the session's first minutes,
        // but only from the session's start.
        let segments = ActivitySegmentation.segments(
            [sample(-3_600, walking: true), sample(600, running: true)],
            from: start,
            to: at(900)
        )
        #expect(segments.first?.start == start)
        #expect(ActivitySegmentation.duration(of: .walking, in: segments) == 600)
        #expect(ActivitySegmentation.duration(of: .running, in: segments) == 300)
    }

    @Test("The durations add up to the session, exactly")
    func theSegmentsPartitionTheSession() {
        let segments = ActivitySegmentation.segments(
            [sample(0, walking: true), sample(600, running: true), sample(1_200, walking: true)],
            from: start,
            to: at(1_800)
        )
        let total = ActivitySegmentation.duration(of: .walking, in: segments)
            + ActivitySegmentation.duration(of: .running, in: segments)
        // « Dominant » is a share; a partial covering would make it a share of
        // something other than the outing.
        #expect(total == 1_800)
    }

    // MARK: - What counts as evidence

    @Test("An unreadable estimate counts as walking, never as running")
    func theFallbackUnderCredits() {
        func activity(_ sample: MotionHistorySample) -> SessionActivity? {
            ActivitySegmentation.segments([sample], from: start, to: at(600)).first?.activity
        }
        // All the ways CoreMotion says nothing useful.
        #expect(activity(self.sample(0)) == .walking)
        #expect(activity(self.sample(0, walking: true, running: true)) == .walking)
        #expect(activity(self.sample(0, running: true, confidence: .low)) == .walking)
        #expect(activity(self.sample(0, running: true, confidence: .unrecognised)) == .walking)
        // The direction is the point: kcalPerStep is 0.04 walking against 0.09
        // running, and the phone writes no energy samples, so this estimate is
        // the only energy figure the session will ever carry. Guessing running
        // invents calories on an immutable workout.
        #expect(SessionActivity.walking.kcalPerStep < SessionActivity.running.kcalPerStep)
        #expect(ActivitySegmentation.fallback == .walking)
    }

    @Test("A confident, unambiguous run is read as a run")
    func aClearRunIsRead() {
        let segments = ActivitySegmentation.segments([sample(0, running: true)], from: start, to: at(600))
        #expect(segments.first?.activity == .running)
    }

    // MARK: - Which activity the session is recorded as

    @Test("A session entirely run is a run, one entirely walked is a walk")
    func aHomogeneousOutingIsItself() {
        let run = ActivitySegmentation.segments([sample(0, running: true)], from: start, to: at(1_800))
        #expect(ActivitySegmentation.dominant(run) == .running)

        let walk = ActivitySegmentation.segments([sample(0, walking: true)], from: start, to: at(1_800))
        #expect(ActivitySegmentation.dominant(walk) == .walking)
    }

    @Test("A mixed outing takes the activity that lasted longest")
    func aMixedOutingTakesTheMajority() {
        // 10 min walking, 20 min running.
        let mostlyRunning = ActivitySegmentation.segments(
            [sample(0, walking: true), sample(600, running: true)],
            from: start,
            to: at(1_800)
        )
        #expect(ActivitySegmentation.dominant(mostlyRunning) == .running)

        // The same outing the other way round.
        let mostlyWalking = ActivitySegmentation.segments(
            [sample(0, running: true), sample(600, walking: true)],
            from: start,
            to: at(1_800)
        )
        #expect(ActivitySegmentation.dominant(mostlyWalking) == .walking)
    }

    @Test("An outing split down the middle is recorded as a walk")
    func aTieUnderCredits() {
        let even = ActivitySegmentation.segments(
            [sample(0, running: true), sample(900, walking: true)],
            from: start,
            to: at(1_800)
        )
        // Half and half is not evidence that it was a run, and the wrong guess
        // is permanent.
        #expect(ActivitySegmentation.duration(of: .running, in: even) == 900)
        #expect(ActivitySegmentation.duration(of: .walking, in: even) == 900)
        #expect(ActivitySegmentation.dominant(even) == .walking)
    }

    // MARK: - Shape of the result

    @Test("A steady walk is one segment, not one per estimate")
    func consecutiveEstimatesAreMerged() {
        // CoreMotion re-states its verdict regularly; a half-hour walk arrives
        // as a long run of identical estimates.
        let repeated = stride(from: 0, through: 1_500, by: 60).map { sample(TimeInterval($0), walking: true) }
        let segments = ActivitySegmentation.segments(repeated, from: start, to: at(1_800))
        #expect(segments.count == 1)
        #expect(segments.first?.duration == 1_800)
    }

    @Test("Estimates arriving out of order are put back in order")
    func unorderedSamplesAreSorted() {
        // The query makes no promise about ordering.
        let segments = ActivitySegmentation.segments(
            [sample(1_200, walking: true), sample(0, walking: true), sample(600, running: true)],
            from: start,
            to: at(1_800)
        )
        #expect(segments.map(\.activity) == [.walking, .running, .walking])
        #expect(segments.map(\.start) == [start, at(600), at(1_200)])
    }

    @Test("A session with no duration has no segments")
    func anEmptyIntervalIsEmpty() {
        #expect(ActivitySegmentation.segments([sample(0, walking: true)], from: start, to: start).isEmpty)
        #expect(ActivitySegmentation.segments([], from: at(600), to: start).isEmpty)
    }

    // MARK: - The bridge out of CoreMotion

    @Test("Confidence mirrors CoreMotion's own constants")
    func confidenceRawValuesMatchCoreMotion() {
        // The bridge maps by raw value, so a drift here would silently re-grade
        // every estimate: confident readings dismissed, or weak ones acted on.
        #expect(MotionActivityConfidence.low.rawValue == CMMotionActivityConfidence.low.rawValue)
        #expect(MotionActivityConfidence.medium.rawValue == CMMotionActivityConfidence.medium.rawValue)
        #expect(MotionActivityConfidence.high.rawValue == CMMotionActivityConfidence.high.rawValue)
        #expect(MotionActivityConfidence(rawValue: 99) == nil)
    }
}

/// Pricing a mixed outing stretch by stretch (issue #247).
///
/// The phone writes **no energy samples at all**, so `estimatedCalories` is the
/// only energy figure a phone-recorded session will ever carry — stored in the
/// workout's metadata, read back by the résumé and the detail sheet, on an
/// immutable `HKWorkout`. A single rate was out by up to 2.25× on a genuinely
/// mixed outing (0.04 kcal/step walking against 0.09 running), and no picker
/// could fix that: ten minutes of walking then twenty of running is neither.
@Suite("Per-activity calories")
struct SegmentedCaloriesTests {
    private let start = Date(timeIntervalSince1970: 1_754_000_000)

    private func session(steps: Int, activity: SessionActivity) -> WalkSession {
        var session = WalkSession(startedAt: start, activity: activity)
        session.steps = steps
        return session
    }

    @Test("Without a breakdown, the figure is exactly what it always was")
    func noBreakdownChangesNothing() {
        // Every session already in Santé was priced this way, and an install
        // where motion recognition is unavailable or refused still is.
        #expect(session(steps: 4_000, activity: .walking).estimatedCalories == 160)
        #expect(session(steps: 4_000, activity: .running).estimatedCalories == 360)
    }

    @Test("A homogeneous outing prices identically with a breakdown")
    func aHomogeneousBreakdownIsANoOp() {
        var walk = session(steps: 4_000, activity: .walking)
        walk.stepsByActivity = [.walking: 4_000]
        // The regression this guards is the silent one: a « better » formula
        // that quietly moves the number on outings it was not meant to change.
        #expect(walk.estimatedCalories == session(steps: 4_000, activity: .walking).estimatedCalories)
    }

    @Test("A mixed outing is the sum of its stretches, not one rate")
    func aMixedOutingIsSummed() {
        var mixed = session(steps: 4_000, activity: .walking)
        mixed.stepsByActivity = [.walking: 1_000, .running: 3_000]

        // 1 000 × 0,04 + 3 000 × 0,09 = 40 + 270.
        #expect(mixed.estimatedCalories == 310)
        // And strictly between the two single-rate answers it replaces — which
        // is the whole claim: neither label was right for this outing.
        #expect(mixed.estimatedCalories > session(steps: 4_000, activity: .walking).estimatedCalories)
        #expect(mixed.estimatedCalories < session(steps: 4_000, activity: .running).estimatedCalories)
    }

    @Test("The label does not price the outing — the stretches do")
    func theRecordedActivityDoesNotChangeTheCost() {
        // A user who set « Marche » and ran for a while chose their label and
        // still ran. Same steps, same stretches, same energy, whichever way the
        // session is filed.
        var asWalk = session(steps: 4_000, activity: .walking)
        asWalk.stepsByActivity = [.walking: 1_000, .running: 3_000]
        var asRun = session(steps: 4_000, activity: .running)
        asRun.stepsByActivity = [.walking: 1_000, .running: 3_000]
        #expect(asWalk.estimatedCalories == asRun.estimatedCalories)
    }

    @Test("An empty breakdown falls back rather than crediting nothing")
    func anEmptyBreakdownIsNotZeroCalories() {
        var session = session(steps: 4_000, activity: .running)
        session.stepsByActivity = [:]
        // Summing an empty dictionary gives zero, and zero calories for four
        // thousand steps is a worse answer than the old formula.
        #expect(session.estimatedCalories == 360)
    }
}
