@preconcurrency import HealthKit

/// The two HealthKit delegates the store answers to.
///
/// In their own file because `WatchWorkoutStore.swift` had outgrown the 500
/// lines SwiftLint allows, and these are the part that reads as plumbing: every
/// callback here does one thing — hop to the main actor and hand the work to a
/// method that can be tested without a delegate at all.

extension WatchWorkoutStore: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // No-op: state transitions are driven from start/stop on the store.
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.handleSessionFailure(message)
        }
    }
}

extension WatchWorkoutStore: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor [weak self] in
            self?.ingest(builder: workoutBuilder)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // No event-specific UI; ignore.
    }
}

/// Automatic walk/run detection during a live session (issue #249).
///
/// In an extension rather than the class body so the state machine above stays
/// the thing you read first, and because none of this is state — the decision
/// is `ActivitySwitchDetector`'s, the stream is `WatchActivityDetection`'s, and
/// what is left here is only the translation into HealthKit's two calls.
