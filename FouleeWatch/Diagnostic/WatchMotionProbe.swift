import Foundation
import Observation

/// The device probe (issue #248), reading `MotionActivitySource`.
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
/// Everything past `MotionActivitySource` is values — `MotionProbeState` and the
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

    @ObservationIgnored private let engine: MotionActivitySource
    @ObservationIgnored private var isStreaming = false

    init(engine: MotionActivitySource = .live()) {
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
    func ingest(_ estimate: MotionActivityEstimate) {
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
