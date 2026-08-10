import CoreMotion
import Foundation
import Observation

/// The CoreMotion boundary of the device probe (issue #248), as four closures.
///
/// Hand-written, because the watch target links no dependency container — the
/// same shape of seam as `WatchRootView.startIntent(syncedTo:)`. It earns its
/// place for one reason: `CMMotionActivityManager.isActivityAvailable()` is
/// `false` on every simulator (verified on watchOS 26.5, where
/// `authorizationStatus()` is `notDetermined` too), so through the real
/// CoreMotion the whole interesting half of `WatchMotionProbe` — the retry that
/// opens the stream the moment the device says it can, and the listening window
/// it resets — is reachable only on a wrist. A probe whose own plumbing is
/// untestable is not an instrument, and it is the plumbing that produced
/// « Disponible : oui » next to « Écoute depuis : flux non ouvert ».
struct MotionProbeEngine {
    var isAvailable: @MainActor () -> Bool
    var authorization: @MainActor () -> MotionProbeAuthorization
    /// Opens the stream; `handler` is called once per estimate.
    var openStream: @MainActor (_ handler: @escaping @Sendable (MotionProbeEstimate) -> Void) -> Void
    var closeStream: @MainActor () -> Void

    /// The real one. A single `CMMotionActivityManager`, captured by the two
    /// closures that need it: allocating it prompts nothing and starts nothing
    /// — the stream, and with it the permission sheet, only opens in
    /// `openStream`.
    @MainActor
    static func live() -> MotionProbeEngine {
        let manager = CMMotionActivityManager()
        return MotionProbeEngine(
            isAvailable: { CMMotionActivityManager.isActivityAvailable() },
            authorization: {
                MotionProbeAuthorization(
                    rawValue: CMMotionActivityManager.authorizationStatus().rawValue
                ) ?? .unrecognised
            },
            openStream: { handler in
                // Delivered on the main queue, and converted to a value
                // immediately: `CMMotionActivity` is a reference type this app
                // must not hold on to.
                manager.startActivityUpdates(to: .main) { activity in
                    guard let activity else { return }
                    handler(MotionProbeEstimate(activity, receivedAt: .now))
                }
            },
            closeStream: { manager.stopActivityUpdates() }
        )
    }
}

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
/// Everything past `MotionProbeEngine` is values — `MotionProbeState` and the
/// pure formatting of `MotionProbeReport` — so nothing here needs a device to
/// exercise: `WatchMotionProbeStreamTests` drives the stream's lifecycle
/// through a fake engine, `WatchMotionProbeReportTests` the display.
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

    @ObservationIgnored private let engine: MotionProbeEngine
    @ObservationIgnored private var isStreaming = false

    init(engine: MotionProbeEngine = .live()) {
        self.engine = engine
    }

    /// The two class-level answers. Cheap, and re-read on a timer because
    /// `authorizationStatus()` is what changes when the user answers the
    /// system prompt — the whole of question 2.
    func refreshCapabilities() {
        state.isAvailable = engine.isAvailable()
        state.authorization = engine.authorization()
    }

    /// Open the stream. Idempotent, and safe to call on every tick — which is
    /// what `keepListening(interval:)` does.
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
        state.openWindow(at: now)
        engine.openStream { [weak self] estimate in
            Task { @MainActor in self?.ingest(estimate) }
        }
    }

    /// Close the stream. Called when the screen goes away, so the probe costs
    /// nothing while it is not being read — and the readings go with it, since
    /// they describe a window that has just ended.
    func stop() {
        guard isStreaming else { return }
        isStreaming = false
        engine.closeStream()
        state.closeWindow()
    }

    /// Record one estimate. Internal and pure so the count / age rows can be
    /// driven from a test without any motion.
    func ingest(_ estimate: MotionProbeEstimate) {
        state.estimateCount += 1
        state.latest = estimate
    }

    /// Keeps the probe live while the screen is up: re-reads the two
    /// capability answers *and re-attempts the open* on every tick. Runs from
    /// the view's `.task`, so it is cancelled on disappear.
    ///
    /// The retry is the point. Availability and authorization are not
    /// necessarily true at the instant the screen appears — whether they
    /// resolve a moment later is question 2, i.e. the very unknown this probe
    /// exists to settle — and a single attempt from `.task` would leave the
    /// screen reporting a capability it has and does not use, forever. Nobody
    /// standing outdoors mid-outing could guess that closing and reopening
    /// « Diagnostic » would fix it, and questions 2 to 4 would go unanswered
    /// for that trip. `start()` returns immediately once the stream is open,
    /// so the retry costs a pair of reads a second.
    func keepListening(interval: Duration = .seconds(1)) async {
        while !Task.isCancelled {
            start()
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
