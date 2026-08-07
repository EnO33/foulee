@preconcurrency import HealthKit
import os
import WatchKit

// periphery:ignore - instantiated by WatchKit via @WKApplicationDelegateAdaptor.
/// Routes the system's crash-recovery launch into `WatchWorkoutRecovery`.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        WatchWorkoutRecovery.run()
    }
}

/// An `HKWorkoutSession` outlives the app process: after a crash, forced
/// termination or reboot mid-walk, the session keeps running system-side but
/// the relaunched app starts at `.idle` and the walk would never be saved.
/// Recover the orphaned session and finish it silently so the workout lands
/// in Santé (streak + stats) instead of being stranded.
enum WatchWorkoutRecovery {
    /// Called from both app init and `handleActiveWorkoutRecovery` — whichever
    /// fires first wins, the other becomes a no-op.
    private static let started = OSAllocatedUnfairLock(initialState: false)

    static func run() {
        #if DEBUG
        // Capture mode (issue #239) writes nothing to Santé, and recovery's
        // whole job is a write: it finishes a stranded session into an
        // `HKWorkout`. Guarded here rather than at the two call sites so both
        // the app's init and the system's crash-recovery entry point are
        // covered by one line.
        guard !WatchScreenshotMode.isActive else { return }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let shouldRun = started.withLock { started -> Bool in
            guard !started else { return false }
            started = true
            return true
        }
        guard shouldRun else { return }
        let store = HKHealthStore()
        store.recoverActiveWorkoutSession { session, _ in
            guard let session else { return }
            let builder = session.associatedWorkoutBuilder()
            session.end()
            builder.endCollection(withEnd: .now) { _, _ in
                builder.finishWorkout { _, _ in }
            }
        }
    }
}
