import FouleeKit
import Foundation

/// A session that outlived the app (issue #554).
///
/// In its own file because `WatchWorkoutStore.swift` is at the 500 lines
/// SwiftLint allows; what is left here is the order things happen in, and
/// every state it sets is the store's own.
extension WatchWorkoutStore {
    /// Pick up the session watchOS kept running while the app was gone,
    /// instead of the second session the wearer would start.
    ///
    /// The outing keeps its identifier, read back from the leg's stamp, so
    /// the next leg joins it in Santé; the legs it saved before are read back
    /// so the screen totals the whole outing. What the app measured itself
    /// and lost with it — the route so far, the climb of the leg — starts
    /// again from here.
    ///
    /// No-op unless idle with a session to recover; never prompts.
    func recover() async {
        guard case .idle = state, !isRecovering else { return }
        #if DEBUG
        // Capture mode (issue #239): nothing reaches HealthKit.
        guard !WatchScreenshotMode.isActive else { return }
        #endif
        guard healthKit.isAvailable() else { return }
        isRecovering = true
        defer { isRecovering = false }
        guard let recovered = await healthKit.recoverSession(self) else { return }
        var earlier: [WatchWorkoutSegment] = []
        if let leg = recovered.leg {
            earlier = await healthKit.savedLegs(leg.outingID)
        }
        await adopt(
            recovered.handle,
            activity: recovered.activity,
            legStartedAt: recovered.startedAt,
            after: earlier,
            outing: recovered.leg?.outingID ?? UUID()
        )
        let now = clock()
        // The builder's clock is the truth: whatever it has not counted since
        // the leg began was paused.
        legPausedDuration = max(0, now.timeIntervalSince(recovered.startedAt) - recovered.elapsed)
        if recovered.isPaused {
            pausedSince = now
            detection.stop()
        }
        refreshActivityTotals(at: now)
        FouleeLog.session.notice("séance reprise, \(earlier.count, privacy: .public) jambe(s) avant")
    }
}
