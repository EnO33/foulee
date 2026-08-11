@preconcurrency import CoreMotion
import Foundation

extension MotionActivityHistory {
    /// The real one.
    ///
    /// A fresh `CMMotionActivityManager` per query, captured by the
    /// continuation so it outlives the call: the query is one-shot, nothing is
    /// subscribed, and there is no stream to keep alive between sessions.
    ///
    /// Guarded on availability because Apple documents the behaviour of the
    /// query as undefined when activity data is unavailable — and this runs at
    /// the moment a session ends, where a crash would cost the walk the user
    /// just finished.
    static let liveValue = MotionActivityHistory(
        samples: { from, to in
            guard CMMotionActivityManager.isActivityAvailable() else { return [] }
            let manager = CMMotionActivityManager()
            return await withCheckedContinuation { continuation in
                // Delivered on a queue of our own rather than `.main`: the
                // session-stop path is already saving a workout on the main
                // actor, and a history query has nothing to do there.
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                manager.queryActivityStarting(from: from, to: to, to: queue) { activities, _ in
                    // The manager is read here on purpose — capturing it keeps
                    // it alive until the handler runs.
                    _ = manager
                    continuation.resume(returning: (activities ?? []).map(MotionHistorySample.init))
                }
            }
        }
    )
}

extension MotionHistorySample {
    /// The CoreMotion boundary, in full.
    ///
    /// The two flags are copied unreduced: they are not mutually exclusive and
    /// can both be false, so any attempt to pick a winner *here* would hide the
    /// ambiguity from `ActivitySegmentation`, the one place equipped to judge
    /// it. The other four — stationary, unknown, cycling, automotive — are not
    /// read: Foulée records none of them, so they could only ever produce « no
    /// evidence », which two clear booleans already produce.
    init(_ activity: CMMotionActivity) {
        self.init(
            startDate: activity.startDate,
            confidence: MotionActivityConfidence(rawValue: activity.confidence.rawValue) ?? .unrecognised,
            walking: activity.walking,
            running: activity.running
        )
    }
}
