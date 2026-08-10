import Foundation

/// Runs `ActivitySwitchDetector` against the live CoreMotion stream for the
/// length of one session (issue #249).
///
/// Everything that is a *decision* lives in the detector, which is pure;
/// everything that is a *lifetime* lives here: when the stream opens, when it
/// closes, and what happens when the device is not ready at the instant the
/// session starts. Split that way because the second half is the part no
/// simulator can drive through real CoreMotion —
/// `CMMotionActivityManager.isActivityAvailable()` is false on all of them —
/// and it is the half that failed first in issue #248.
///
/// The watch is the one place this can work at all: a running
/// `HKWorkoutSession` keeps the app alive, so the stream keeps delivering. The
/// same code on iPhone would go silent the moment the phone went in a pocket.
@MainActor
final class WatchActivityDetection {
    private let source: MotionActivitySource
    private let confirmations: Int

    private var detector: ActivitySwitchDetector?
    private var onSwitch: ((ActivitySwitchDetector.Switch) -> Void)?
    private var opening: Task<Void, Never>?
    private var isStreaming = false

    /// - Parameter confirmations: passed straight to `ActivitySwitchDetector`,
    ///   whose own default is the shipped value. Surfaced here so a test can
    ///   demand more of it without this file having an opinion about how many.
    init(
        source: MotionActivitySource = .live(),
        confirmations: Int = ActivitySwitchDetector.defaultConfirmations
    ) {
        self.source = source
        self.confirmations = confirmations
    }

    /// Begin classifying, for a session started as `activity` at `date`.
    ///
    /// `onSwitch` fires on the main actor, once per confirmed change.
    func start(
        from activity: SessionActivity,
        at date: Date,
        retryInterval: Duration = .seconds(1),
        maximumAttempts: Int = 30,
        onSwitch: @escaping (ActivitySwitchDetector.Switch) -> Void
    ) {
        stop()
        detector = ActivitySwitchDetector(startedAs: activity, at: date, confirmations: confirmations)
        self.onSwitch = onSwitch
        opening = Task { [weak self] in
            await self?.keepOpening(interval: retryInterval, maximumAttempts: maximumAttempts)
        }
    }

    /// Close the stream and forget the session. Idempotent — `start` calls it
    /// too, so a session that somehow begins twice cannot leave two streams
    /// open.
    func stop() {
        opening?.cancel()
        opening = nil
        detector = nil
        onSwitch = nil
        guard isStreaming else { return }
        isStreaming = false
        source.closeStream()
    }

    /// Record one estimate and report a switch if it confirms one.
    ///
    /// Internal rather than private so the whole rule — stream to store — is
    /// drivable from a test without any motion.
    func ingest(_ estimate: MotionActivityEstimate) {
        guard var detector else { return }
        let confirmed = detector.observe(estimate)
        self.detector = detector
        guard let confirmed else { return }
        onSwitch?(confirmed)
    }

    /// Retry opening until it takes, or until the attempts run out.
    ///
    /// The retry is not defensive padding: issue #248 shipped with a single
    /// attempt and produced a screen reporting a capability it had and did not
    /// use, for as long as it was left open. Here the equivalent failure is
    /// worse and quieter — detection that never runs for a whole outing, with
    /// nothing on screen to say so.
    ///
    /// Bounded, unlike the probe's: availability is a property of the hardware,
    /// so if it has not resolved within half a minute it is not going to, and a
    /// session lasts an hour. Authorization is *not* waited on — the first
    /// `openStream` is what raises the prompt.
    private func keepOpening(interval: Duration, maximumAttempts: Int) async {
        for _ in 0..<maximumAttempts {
            if Task.isCancelled || openStream() { return }
            try? await Task.sleep(for: interval)
        }
    }

    /// - Returns: whether the stream is open.
    private func openStream() -> Bool {
        guard !isStreaming else { return true }
        // `startActivityUpdates` is documented as undefined when activity data
        // is unavailable, and a crash here happens mid-outing, on a wrist.
        guard source.isAvailable() else { return false }
        isStreaming = true
        source.openStream { [weak self] estimate in
            Task { @MainActor in self?.ingest(estimate) }
        }
        return true
    }
}
