import Foundation

/// Which screen the watch shows, given the session state and whether the
/// owner opened the diagnostic (issue #248).
///
/// Extracted from `WatchRootView.body` for the reason `WatchIdleScreen` was:
/// a decision made inside a `View` body is unassertable, and this one carries
/// a promise worth pinning — **the probe observes, it does not interfere**.
/// `.diagnostic` covers whatever is underneath and hands it back untouched;
/// no case here starts, stops or alters a workout, and closing the screen
/// returns to the very session that was running.
enum WatchRoute: Equatable {
    case diagnostic
    case idle
    case active(WatchWorkoutMetrics)
    case ended(WatchWorkoutMetrics, saveFailed: Bool)

    static func resolve(state: WatchWorkoutStore.State, isShowingDiagnostic: Bool) -> WatchRoute {
        // The diagnostic wins over every session state on purpose: the
        // measurements that matter — transition latency, battery cost over
        // 30–60 min — are the ones taken *during* a real outing, so the screen
        // has to be readable while a workout is recording.
        if isShowingDiagnostic { return .diagnostic }
        switch state {
        case .idle: return .idle
        case .active(let metrics): return .active(metrics)
        case .ended(let metrics, let saveFailed): return .ended(metrics, saveFailed: saveFailed)
        }
    }
}
