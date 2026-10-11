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

    /// The session is named, not just the error (issue #290).
    ///
    /// Since issue #265 an outing opens one session per leg and the store is
    /// the delegate of every one of them. `HKError.errorAnotherWorkoutSessionStarted`
    /// is delivered to the session that has just been *superseded* — so opening
    /// the next leg makes the previous one fail, by design. Handing that to the
    /// store unattributed is what ended a real sortie on its second switch.
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        let message = error.localizedDescription
        let session = ObjectIdentifier(workoutSession)
        Task { @MainActor [weak self] in
            self?.handleSessionFailure(message, from: session)
        }
    }

    /// A request from the phone (issue #282).
    ///
    /// **An array**, like the phone's side: HealthKit caches and delivers in
    /// batches. Duplicates are harmless — `stop()` guards on `.active`, so the
    /// second one is a no-op.
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        let decoder = JSONDecoder()
        let commands = data.compactMap { try? decoder.decode(MirrorCommand.self, from: $0) }
        guard !commands.isEmpty else { return }
        let session = ObjectIdentifier(workoutSession)
        Task { @MainActor [weak self] in
            for command in commands {
                await self?.handle(command, from: session)
            }
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
extension WatchWorkoutStore {
    /// Start classifying. **Records nothing into the session** — see
    /// `applySwitch`.
    /// Read the session's own counters as a second, much faster opinion on
    /// what the wearer is doing (issue #267).
    ///
    /// CoreMotion takes around thirty seconds to change its mind — its
    /// smoothing is its purpose. Cadence and speed change within one window,
    /// and they cost nothing new: these are the counters already driving the
    /// screen. Both feed the same detector, so nothing about the decision
    /// depends on which noticed first.
    func beginActivityDetection(from activity: SessionActivity) {
        let now = clock()
        currentActivity = activity
        detection.start(from: activity, at: now) { [weak self] confirmed in
            self?.applySwitch(confirmed)
        }
    }

    /// Note the change on screen at once, and queue the recording.
    ///
    /// **The two halves move at different speeds on purpose.** Renaming cannot
    /// fail and cannot be wrong for long — the next reading corrects it. Cutting
    /// the outing in two writes a permanent workout into Santé, so it waits
    /// until the new sport has held for `minimumLegDuration` — counted from
    /// `confirmed.confirmedAt`, the moment it was decided (issue #331).
    ///
    /// Waiting costs no accuracy: the split carries `confirmed.date`, the
    /// instant the sport actually changed, and both HealthKit calls accept a
    /// past date.
    func applySwitch(_ confirmed: ActivitySwitchDetector.Switch) {
        guard case .active = state else { return }
        currentActivity = confirmed.activity
        refreshActivityTotals(at: clock())
        // Back to what the leg is already recording: whatever was queued is
        // moot, and no workout was created — which is the whole point of
        // waiting.
        pendingSplit = confirmed.activity == legActivity ? nil : confirmed
    }
}
