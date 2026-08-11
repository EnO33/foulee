import Foundation

/// What the wrist tells the phone, and how often (issue #278).
///
/// **Not one message per second.** HealthKit caches what a mirrored session
/// sends and wakes the iOS app *periodically* — potentially minutes apart —
/// so everything sent between two wakes is discarded whatever it was. A higher
/// rate buys no freshness at all, and costs CPU on a watch already running a
/// session, a motion stream and a per-second clock. Apple documents that a
/// workout app can be suspended for excessive CPU use; this is not the place
/// to spend it.
///
/// So: one snapshot every `mirrorInterval`, plus the moments that carry
/// information a tick cannot — the outing starting, the sport changing, the
/// outing ending.
extension WatchWorkoutStore {
    /// Long enough to be free, short enough that a phone woken at any moment
    /// finds something recent. Nothing hangs on the exact figure — the phone
    /// dates what it shows.
    static let mirrorInterval: TimeInterval = 8

    /// Send if the interval has elapsed. Called from every HealthKit delivery,
    /// which is far more often than this fires.
    ///
    /// Riding on `ingest` rather than a timer of its own is deliberate: a timer
    /// is another wakeup, and there is nothing to say when HealthKit has said
    /// nothing. If deliveries stop, the phone stops hearing — and shows the age
    /// of what it last heard, which is the truth.
    /// **Only while the outing is running.** A periodic send from an ended
    /// session would carry `isEnded: false` and un-end, on the phone, an outing
    /// that is over.
    func mirrorIfDue(at now: Date) async {
        guard case .active(let metrics) = state else { return }
        if let last = lastMirrorSendAt, now.timeIntervalSince(last) < Self.mirrorInterval {
            return
        }
        await mirrorNow(metrics, at: now, isEnded: false)
    }

    /// The sport changed — say so at once rather than let the phone name the
    /// previous one for up to an interval.
    ///
    /// Dated `.now`, **never the boundary**. A split is back-dated by up to
    /// `minimumLegDuration`, so a snapshot stamped with the boundary would be
    /// older than the last periodic send and the phone would drop it on its
    /// newest-wins rule — the send would look done and change nothing.
    func mirrorSwitch() async {
        guard case .active(let metrics) = state else { return }
        await mirrorNow(metrics, at: .now, isEnded: false)
    }

    /// Send regardless of the interval — for the moments that carry something a
    /// tick cannot.
    ///
    /// The metrics are passed in rather than read from `state`, because the
    /// most important send of all happens *before* the state becomes `.ended`:
    /// `sendToRemoteWorkoutSession` needs a session that is still alive, so the
    /// final snapshot has to go out ahead of `end()` and `finishWorkout()`.
    func mirrorNow(_ metrics: WatchWorkoutMetrics, at now: Date, isEnded: Bool) async {
        #if DEBUG
        // Capture mode (issue #239): the seeded session is a fiction. Sending
        // it would push fabricated figures to a real paired iPhone.
        guard !WatchScreenshotMode.isActive else { return }
        #endif
        guard let handle = sessionHandle else { return }
        let snapshot = metrics.snapshot(at: now, isEnded: isEnded)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        lastMirrorSendAt = now
        do {
            try await handle.sendToRemote(data)
        } catch {
            // The ordinary case, not the exception: no phone is mirroring.
            // Swallowed on purpose — a wrist that cannot reach a phone is still
            // a wrist that is recording perfectly well.
            FouleeLog.session.notice(
                "snapshot non transmis : \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
