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
    /// Everything else yields `noEvidence` without needing a case of its own:
    /// both flags clear is what a stationary wearer, a bike ride, a car journey
    /// and an estimate the device could not classify all look like from here.
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
/// ## Why there is almost no hysteresis
///
/// There used to be one — two consecutive consistent readings — and the reason
/// was that a switch cost a **permanent segment in Santé**, on a workout that
/// is immutable and that Foulée cannot delete. That reason is gone: since
/// issue #256 a switch writes nothing at all, because HealthKit refuses a
/// subactivity of another sport. All a switch costs now is the word on screen.
///
/// The trade therefore flips. Waiting for a second reading bought protection
/// against a record that no longer exists, and it cost real seconds on top of
/// CoreMotion's own latency — two delays added together, on a feature whose
/// first field report was « c'est lent ». So: **one consistent reading**, above
/// the confidence floor. A wrong guess corrects itself on the next estimate.
///
/// `confirmations` remains, and remains tested: if the field ever shows the
/// label flapping, raising it is one number — and the day segmenting becomes
/// possible again, it must go back up with it.
struct ActivitySwitchDetector: Sendable {
    /// A confirmed change: the activity to switch to, and when it started.
    struct Switch: Equatable, Sendable {
        var activity: SessionActivity
        var date: Date
    }

    /// How many consecutive readings of the *other* activity confirm a switch.
    let confirmations: Int

    /// What ships: one. See the note above — the hysteresis protected a
    /// permanent record that no longer exists.
    static let defaultConfirmations = 1
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
        confirmations: Int = defaultConfirmations,
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
