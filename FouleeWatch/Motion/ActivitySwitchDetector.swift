import Foundation

/// What one estimate says about the two activities Foulée records.
///
/// `noEvidence` is a first-class answer, not an error: CoreMotion asserting
/// nothing is a frequent, normal reading — `CMMotionActivity`'s flags can all
/// be false — and so is asserting something Foulée does not record (cycling,
/// a car). Both mean *the same thing here*: no reason to change what the
/// session is recording.
enum MotionActivityReading: Equatable, Sendable {
    case activity(SessionActivity)
    case noEvidence
}

extension MotionActivityEstimate {
    /// Reduce the six booleans to at most one activity.
    ///
    /// Only `walking` and `running` are consulted, and **exactly one** of them
    /// must be set. `if walking … else if running` would be wrong by
    /// construction: the flags are not mutually exclusive, so that form silently
    /// prefers walking whenever the device asserts both — precisely the moment
    /// it is least sure.
    ///
    /// Everything else — stationary, cycling, automotive, unknown, all-false —
    /// leaves both of those two clear and therefore yields `noEvidence` without
    /// needing a case of its own.
    func reading(minimumConfidence: MotionActivityConfidence) -> MotionActivityReading {
        guard confidence >= minimumConfidence else { return .noEvidence }
        switch (walking, running) {
        case (true, false): return .activity(.walking)
        case (false, true): return .activity(.running)
        default: return .noEvidence
        }
    }
}

/// Decides when a live session should stop recording one activity and start
/// recording the other (issue #249).
///
/// Pure and value-typed: it holds no clock, no CoreMotion and no HealthKit, so
/// every rule below is exercised on a Mac from hand-built sequences. The
/// side effects — `HKWorkoutSession.beginNewActivity` / `endCurrentActivity` —
/// belong to `WatchWorkoutStore`, which only ever acts on what this returns.
///
/// ## Why the hysteresis is small
///
/// The instinct is to smooth hard, because a switch costs a permanent segment
/// in Santé. The device measurement of issue #248 says otherwise:
/// `CMMotionActivityManager` **already smooths**, and its latency *is* that
/// smoothing — a walk→run transition surfaced in under 30 s, cleanly, with no
/// flapping in between. Stacking a long confirmation window on top would add
/// the two delays: the screen would name the wrong sport for a full minute and
/// the segment boundary written to Santé would be off by as much.
///
/// So: require the minimum that protects against a single aberrant estimate —
/// two consecutive consistent readings — and nothing more. If the field shows
/// flapping, `confirmations` is the one number to raise.
struct ActivitySwitchDetector: Sendable {
    /// A confirmed change: the activity to switch to, and when it started.
    struct Switch: Equatable, Sendable {
        var activity: SessionActivity
        var date: Date
    }

    /// How many consecutive readings of the *other* activity confirm a switch.
    let confirmations: Int
    /// Readings below this are not evidence.
    ///
    /// `.medium`, and deliberately not `.low`. The two failure modes are not
    /// symmetric: too strict and detection goes quiet, which leaves the session
    /// exactly as the wearer started it — today's behaviour, no data harmed.
    /// Too lax and a noisy estimate writes a wrong segment into Santé, where
    /// `HKWorkout` is immutable and Foulée has no delete path. Between a
    /// feature that under-fires and a record that is wrong forever, the record
    /// wins.
    ///
    /// `.unrecognised` — a level this app cannot name — sorts below `.low` and
    /// is therefore rejected too, for the same reason.
    let minimumConfidence: MotionActivityConfidence
    /// How long a half-confirmed candidate survives without further support.
    ///
    /// Without it, "two consecutive readings" would happily pair an aberrant
    /// estimate with another one ten minutes later — the stream goes quiet
    /// whenever the device asserts nothing, and quiet readings must not count
    /// as agreement.
    let staleAfter: TimeInterval

    /// What the session is recording right now.
    private(set) var current: SessionActivity
    /// Start of the current segment. Every boundary this detector emits is
    /// clamped to be at or after it, so segments can never overlap however odd
    /// the device's own `startDate` turns out to be.
    private var boundary: Date

    private var candidate: SessionActivity?
    private var candidateCount = 0
    private var candidateSince: Date?
    private var candidateLastSeen: Date?

    /// - Parameters:
    ///   - startedAs: what the session was started as — the wearer's choice, or
    ///     the synced preference. There is no "unknown" starting state: until
    ///     the device says otherwise, the session is what it was opened as.
    ///   - at: the session start, and the earliest possible segment boundary.
    init(
        startedAs: SessionActivity,
        at date: Date,
        confirmations: Int = 2,
        minimumConfidence: MotionActivityConfidence = .medium,
        staleAfter: TimeInterval = 90
    ) {
        current = startedAs
        boundary = date
        self.confirmations = confirmations
        self.minimumConfidence = minimumConfidence
        self.staleAfter = staleAfter
    }

    /// Feed one estimate. Returns a switch only when one is confirmed.
    ///
    /// A reading that agrees with the current activity cancels any pending
    /// candidate outright: that is what makes a lone spurious estimate
    /// harmless, and it is the rule the noisy-sequence test leans on.
    mutating func observe(_ estimate: MotionActivityEstimate) -> Switch? {
        guard case .activity(let seen) = estimate.reading(minimumConfidence: minimumConfidence) else {
            // Neutral, not contradicting: the device asserting nothing is not a
            // reason to abandon a candidate, only a reason not to advance it.
            // Staleness, not silence, is what expires a candidate.
            return nil
        }
        guard seen != current else {
            forgetCandidate()
            return nil
        }
        advanceCandidate(to: seen, with: estimate)
        guard candidateCount >= confirmations, let since = candidateSince else { return nil }

        let date = min(max(since, boundary), estimate.receivedAt)
        current = seen
        boundary = date
        forgetCandidate()
        return Switch(activity: seen, date: date)
    }

    /// Extend the streak, or open a new one when the candidate changed or the
    /// previous support has gone stale.
    private mutating func advanceCandidate(to seen: SessionActivity, with estimate: MotionActivityEstimate) {
        let expired = candidateLastSeen.map { estimate.receivedAt.timeIntervalSince($0) > staleAfter } ?? true
        if candidate == seen, !expired {
            candidateCount += 1
        } else {
            candidate = seen
            candidateCount = 1
            // The *first* estimate of the streak dates the boundary, not the
            // confirming one. CoreMotion's `startDate` is when the device says
            // the activity began, so this is what claws back most of the
            // detection latency instead of stamping the segment 30 s late.
            candidateSince = estimate.startDate
        }
        candidateLastSeen = estimate.receivedAt
    }

    private mutating func forgetCandidate() {
        candidate = nil
        candidateCount = 0
        candidateSince = nil
        candidateLastSeen = nil
    }
}
