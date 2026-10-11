import Foundation

/// Pause and resume an outing started on the wrist (issue #384).
///
/// Three things have to stop together, or a pause would lie somewhere:
/// - **HealthKit**: `HKWorkoutSession.pause()` leaves the stretch out of the
///   saved workout's duration;
/// - **the clock**: the leg in flight leaves paused time out of its elapsed, so
///   the outing's totals, its kilometres and its pace all exclude it;
/// - **detection**: standing still at a crossing is not a change of sport, so
///   the classifier is stopped and any queued switch dropped — a pause never
///   cuts a leg.
extension WatchWorkoutStore {
    var isPaused: Bool { pausedSince != nil }

    /// Pause the outing in flight. No-op when it is not running.
    func pause(at now: Date = .now) {
        guard case .active = state, pausedSince == nil else { return }
        pausedSince = now
        sessionHandle?.pause()
        detection.stop()
        pendingSplit = nil
        refreshActivityTotals(at: now)
        Task { await mirrorSwitch() }
    }

    /// Resume where the outing stopped. No-op when it is not paused.
    func resume(at now: Date = .now) {
        guard case .active = state, let since = pausedSince else { return }
        legPausedDuration += max(0, now.timeIntervalSince(since))
        pausedSince = nil
        sessionHandle?.resume()
        beginActivityDetection(from: currentActivity)
        refreshActivityTotals(at: now)
        Task { await mirrorSwitch() }
    }

    /// A new leg, or a new outing, starts with nothing paused.
    func resetPause() {
        legPausedDuration = 0
        pausedSince = nil
    }
}
