import Foundation

/// Runs `ActivitySwitchDetector` against the live motion streams for the
/// length of one session (issues #249, #331).
///
/// Everything that is a *decision* lives in the detector and in
/// `MovementClassifier`, which are pure; everything that is a *lifetime* lives
/// here: when the streams open, when they close, and what happens when the
/// device is not ready at the instant the session starts. Split that way
/// because the second half is the part no simulator can drive through real
/// CoreMotion — neither `CMMotionActivityManager.isActivityAvailable()` nor the
/// pedometer's cadence is available on any of them — and it is the half that
/// failed first in issue #248.
///
/// Two streams, one per source of `ActivityObservation`:
///
/// - `CMMotionActivityManager`, slow (~30 s) and right;
/// - `CMPedometer`'s instantaneous cadence and pace, quick and personal.
///
/// The watch is the one place this can work at all: a running
/// `HKWorkoutSession` keeps the app alive, so the streams keep delivering. The
/// same code on iPhone would go silent the moment the phone went in a pocket.
@MainActor
final class WatchActivityDetection {
    /// How long a pedometer cadence stays worth showing (issue #331). Past
    /// this the stream has gone quiet — the wearer stopped, or the pedometer
    /// did — and a frozen figure would claim a rhythm nobody is keeping.
    static let cadenceShelfLife: TimeInterval = 10

    private let source: MotionActivitySource
    private let pedometer: PedometerSource
    private let confirmations: Int

    private var detector: ActivitySwitchDetector?
    private var onSwitch: ((ActivitySwitchDetector.Switch) -> Void)?
    private var opening: Task<Void, Never>?
    private var sessionStart = Date.distantPast
    private var isStreamingActivity = false
    private var isStreamingPedometer = false
    /// The pedometer's latest update. Dates the next one's boundary, and is
    /// what the screen reads as the live cadence.
    private var lastPedometerReading: PedometerReading?

    /// - Parameter confirmations: passed straight to `ActivitySwitchDetector`,
    ///   whose own default is the shipped value. Surfaced here so a test can
    ///   demand more of it without this file having an opinion about how many.
    init(
        source: MotionActivitySource = .live(),
        pedometer: PedometerSource = .live(),
        confirmations: Int = ActivitySwitchDetector.defaultConfirmations
    ) {
        self.source = source
        self.pedometer = pedometer
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
        sessionStart = date
        self.onSwitch = onSwitch
        opening = Task { [weak self] in
            await self?.keepOpening(interval: retryInterval, maximumAttempts: maximumAttempts)
        }
    }

    /// Close the streams and forget the session. Idempotent — `start` calls it
    /// too, so a session that somehow begins twice cannot leave two streams
    /// open.
    func stop() {
        opening?.cancel()
        opening = nil
        detector = nil
        onSwitch = nil
        lastPedometerReading = nil
        if isStreamingActivity {
            isStreamingActivity = false
            source.closeStream()
        }
        if isStreamingPedometer {
            isStreamingPedometer = false
            pedometer.closeStream()
        }
    }

    /// Steps per second right now, or `nil` when the pedometer has nothing
    /// recent to say (issue #331).
    func cadence(at now: Date) -> Double? {
        guard let reading = lastPedometerReading,
              now.timeIntervalSince(reading.date) <= Self.cadenceShelfLife
        else { return nil }
        return reading.cadence
    }

    /// Record one CoreMotion estimate and report a switch if it confirms one.
    ///
    /// Internal rather than private so the whole rule — stream to store — is
    /// drivable from a test without any motion.
    func ingest(_ estimate: MotionActivityEstimate) {
        guard let detector else { return }
        record(estimate.observation(minimumConfidence: detector.minimumConfidence), from: "coremotion")
    }

    /// Record one pedometer update (issue #331).
    func ingest(_ reading: PedometerReading) {
        guard detector != nil else { return }
        let previous = lastPedometerReading?.date
        lastPedometerReading = reading
        guard let observation = MovementClassifier.observation(reading, since: previous) else { return }
        record(observation, from: "podomètre")
    }

    /// The one place an observation meets the detector, whichever source made
    /// it (issue #267) — and the log, so a segment nobody walked can be traced
    /// to the reading that cut it (issue #331).
    private func record(_ observation: ActivityObservation, from origin: String) {
        guard var detector else { return }
        FouleeLog.detection.info(
            """
            \(origin, privacy: .public) : \(observation.reading.logText, privacy: .public) \
            depuis \(observation.began.timeIntervalSince(self.sessionStart), format: .fixed(precision: 1), privacy: .public) s, \
            vu à \(observation.observed.timeIntervalSince(self.sessionStart), format: .fixed(precision: 1), privacy: .public) s
            """
        )
        let confirmed = detector.observe(observation)
        self.detector = detector
        guard let confirmed else { return }
        FouleeLog.detection.notice(
            """
            bascule vers \(confirmed.activity.label, privacy: .public), \
            frontière à \(confirmed.date.timeIntervalSince(self.sessionStart), format: .fixed(precision: 1), privacy: .public) s
            """
        )
        onSwitch?(confirmed)
    }

    /// Retry opening until both streams take, or until the attempts run out.
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
            if Task.isCancelled || openStreams() { return }
            try? await Task.sleep(for: interval)
        }
        FouleeLog.detection.error(
            """
            flux incomplets après \(maximumAttempts, privacy: .public) essais : \
            activité \(self.isStreamingActivity, privacy: .public), podomètre \(self.isStreamingPedometer, privacy: .public)
            """
        )
    }

    /// - Returns: whether both streams are open.
    private func openStreams() -> Bool {
        // `startActivityUpdates` is documented as undefined when activity data
        // is unavailable, and a crash here happens mid-outing, on a wrist.
        if !isStreamingActivity, source.isAvailable() {
            isStreamingActivity = true
            source.openStream { [weak self] estimate in
                Task { @MainActor in self?.ingest(estimate) }
            }
        }
        if !isStreamingPedometer, pedometer.isAvailable() {
            isStreamingPedometer = true
            pedometer.openStream(sessionStart) { [weak self] reading in
                Task { @MainActor in self?.ingest(reading) }
            }
        }
        return isStreamingActivity && isStreamingPedometer
    }
}

private extension MotionActivityReading {
    /// « marche », « course » or « sans avis » — what the log line says.
    var logText: String {
        switch self {
        case .activity(let activity): activity.label.lowercased()
        case .noEvidence: "sans avis"
        }
    }
}
