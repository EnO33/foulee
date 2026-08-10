import CoreMotion
import Foundation
import Observation

/// The one place in the app that talks to CoreMotion (issue #248).
///
/// This is a **diagnostic instrument, not a feature**. It answers four
/// questions no simulator can settle — does `isActivityAvailable()` return
/// true on a real Apple Watch, what does the authorization flow actually do,
/// how many seconds pass before a flag flips when a run starts, and what a
/// continuous stream costs over a 30–60 min outing. Until those are known,
/// building activity detection on top would be building on sand.
///
/// It **observes and nothing else**: it starts no workout, stops none, writes
/// nothing to Santé and touches no store. Opening it during a session leaves
/// the session running (`WatchRoute` covers that as a test).
///
/// Everything past the CoreMotion boundary is `MotionProbeState`, a value —
/// the copy below is the only line of this file that a device is needed to
/// exercise. The formatting, and therefore everything the screen claims, is
/// pure and covered by `WatchMotionProbeReportTests`.
///
/// **Not** wrapped in `#if DEBUG`, unlike `WatchScreenshotMode`. The capture
/// mode runs on the developer's Mac, so compiling it out of Release costs
/// nothing; this runs on a wrist, outdoors, and TestFlight — the only way onto
/// a paired Apple Watch — distributes Release builds. A `#if DEBUG` probe
/// would simply not be there. The version carrying it is never submitted to
/// the App Store, and a follow-up issue removes it.
@MainActor
@Observable
final class WatchMotionProbe {
    private(set) var state = MotionProbeState()

    /// Constructed eagerly with the root view. Allocating the manager prompts
    /// nothing and starts nothing — the stream, and with it the permission
    /// sheet, only opens in `start()`.
    @ObservationIgnored private let manager = CMMotionActivityManager()
    @ObservationIgnored private var isStreaming = false

    /// The two class-level answers. Cheap, and re-read on a timer because
    /// `authorizationStatus()` is what changes when the user answers the
    /// system prompt — the whole of question 2.
    func refreshCapabilities() {
        state.isAvailable = CMMotionActivityManager.isActivityAvailable()
        state.authorization = MotionProbeAuthorization(
            rawValue: CMMotionActivityManager.authorizationStatus().rawValue
        ) ?? .unrecognised
    }

    /// Open the stream. Idempotent.
    ///
    /// Guarded on availability: Apple documents the behaviour of
    /// `startActivityUpdates` as undefined when activity data is unavailable,
    /// and a probe that crashes answers nothing. When it *is* unavailable the
    /// screen says so — « Disponible : non » with no stream — which is already
    /// the answer to question 1.
    func start(now: Date = .now) {
        refreshCapabilities()
        guard state.isAvailable, !isStreaming else { return }
        isStreaming = true
        state.startedAt = now
        // Delivered on the main queue, and converted to a value immediately:
        // `CMMotionActivity` is a reference type this app must not hold on to.
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            let estimate = MotionProbeEstimate(activity, receivedAt: .now)
            Task { @MainActor in self?.ingest(estimate) }
        }
    }

    /// Close the stream. Called when the screen goes away, so the probe costs
    /// nothing while it is not being read.
    func stop() {
        guard isStreaming else { return }
        isStreaming = false
        manager.stopActivityUpdates()
    }

    /// Record one estimate. Internal and pure so the count / age rows can be
    /// driven from a test without any motion.
    func ingest(_ estimate: MotionProbeEstimate) {
        state.estimateCount += 1
        state.latest = estimate
    }

    /// Keeps availability and authorization live while the screen is up.
    /// Runs from the view's `.task`, so it is cancelled on disappear.
    func observeCapabilities(interval: Duration = .seconds(1)) async {
        while !Task.isCancelled {
            refreshCapabilities()
            try? await Task.sleep(for: interval)
        }
    }
}

extension MotionProbeEstimate {
    /// The CoreMotion boundary, in full.
    ///
    /// Each flag copied on its own line: `CMMotionActivity`'s booleans are not
    /// mutually exclusive and can all be false at once, so there is no
    /// "primary" one to pick and any attempt to reduce them here would throw
    /// away the exact thing being measured.
    init(_ activity: CMMotionActivity, receivedAt: Date) {
        self.init(
            startDate: activity.startDate,
            receivedAt: receivedAt,
            confidence: MotionProbeConfidence(rawValue: activity.confidence.rawValue) ?? .unrecognised,
            walking: activity.walking,
            running: activity.running,
            stationary: activity.stationary,
            unknown: activity.unknown,
            cycling: activity.cycling,
            automotive: activity.automotive
        )
    }
}
