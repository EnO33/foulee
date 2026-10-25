import FouleeKit
@preconcurrency import HealthKit
import Observation
import WatchKit

// periphery:ignore - instantiated by WatchKit via @WKApplicationDelegateAdaptor.
/// Routes the system's crash-recovery launch into `WatchWorkoutRecovery`.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in WatchWorkoutRecovery.shared.request() }
    }

    /// The phone asked for a session (issue #283).
    ///
    /// This is the whole of `startWatchApp(with:)`'s watch side: the system
    /// wakes the app — launching it if need be — and hands over the
    /// configuration. It arrives *before* any view exists, so it is parked
    /// rather than acted on; `WatchRootView` is what can actually start a
    /// session.
    ///
    /// A sport this app does not record is refused rather than folded into a
    /// walk. Nothing else asks for one today, but stamping Santé with a sport
    /// the wearer did not choose is permanent (issue #223).
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        guard let activity = SessionActivity(workoutConfiguration.activityType) else { return }
        Task { @MainActor in WatchPendingStart.shared.request(activity) }
    }
}

/// An `HKWorkoutSession` outlives the app process: after a crash, forced
/// termination or reboot mid-walk, the session keeps running system-side while
/// the relaunched app starts at `.idle`.
///
/// It used to be finished on the spot, so the walk at least landed in Santé.
/// But the wearer was still walking: they started a second session, and the
/// outing was cut in two (issue #554). The session is now **picked up**, the
/// way Apple's own workout apps do: `WatchWorkoutStore.recover()` adopts it
/// and the session screen comes back.
///
/// The system's recovery launch reaches `WatchAppDelegate` before any view
/// exists, and the store is `@State` inside `WatchRootView`: this is the hop
/// between them, like `WatchPendingStart`. The view also tries once on appear,
/// for a relaunch the system does not route through the delegate.
@MainActor
@Observable
final class WatchWorkoutRecovery {
    static let shared = WatchWorkoutRecovery()

    /// Bumped on each recovery launch; the view recovers when it changes.
    private(set) var requests = 0

    func request() {
        requests += 1
    }
}
