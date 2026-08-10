import Foundation
import Testing
@testable import FouleeWatch

/// The device probe's plumbing (issue #248): when the stream opens, when it
/// closes, and what the readings describe once it has.
///
/// `WatchMotionProbeReportTests` covers the display, which is pure. This suite
/// covers the half that is *not* pure and that no simulator can exercise
/// through CoreMotion — `CMMotionActivityManager.isActivityAvailable()` is
/// `false` on every simulator, so the real engine can never reach the code that
/// matters. `MotionProbeEngine` is the seam that makes it reachable, and both
/// failures pinned here were real readings on the screen before it existed.
@Suite("Watch motion probe stream")
@MainActor
struct WatchMotionProbeStreamTests {
    /// A CoreMotion that does what the test says, including changing its mind.
    @MainActor
    final class FakeMotion {
        var isAvailable = false
        var authorization = MotionProbeAuthorization.notDetermined
        /// Flips availability on once this many reads have happened — a device
        /// whose capability only resolves after the screen is already up.
        var becomesAvailableOnRead: Int?

        private(set) var reads = 0
        private(set) var opens = 0
        private(set) var closes = 0
        private var handler: (@Sendable (MotionProbeEstimate) -> Void)?

        var engine: MotionProbeEngine {
            MotionProbeEngine(
                isAvailable: { [self] in
                    reads += 1
                    if let threshold = becomesAvailableOnRead, reads >= threshold { isAvailable = true }
                    return isAvailable
                },
                authorization: { [self] in authorization },
                openStream: { [self] handler in
                    opens += 1
                    self.handler = handler
                },
                closeStream: { [self] in
                    closes += 1
                    handler = nil
                }
            )
        }

        /// Deliver one estimate the way CoreMotion would.
        func deliver(_ estimate: MotionProbeEstimate) {
            handler?(estimate)
        }
    }

    private let base = Date(timeIntervalSince1970: 1_754_000_000)

    private func estimate(at date: Date, walking: Bool = true) -> MotionProbeEstimate {
        MotionProbeEstimate(
            startDate: date,
            receivedAt: date,
            confidence: .high,
            walking: walking,
            running: false,
            stationary: false,
            unknown: false,
            cycling: false,
            automotive: false
        )
    }

    private func value(of label: String, in state: MotionProbeState, now: Date) -> String? {
        MotionProbeReport.rows(for: state, now: now).first { $0.label == label }?.value
    }

    // MARK: - The stream opens when it can, not only when the screen appeared

    @Test("A capability that only resolves after the screen is up still opens the stream")
    func availabilityArrivingLateStillOpensTheStream() async {
        let motion = FakeMotion()
        // Unavailable on the first two reads, available afterwards.
        motion.becomesAvailableOnRead = 3
        let probe = WatchMotionProbe(engine: motion.engine)

        // Exactly what `WatchMotionProbeView.task` runs.
        let listening = Task { await probe.keepListening(interval: .milliseconds(20)) }
        await waitUntil { probe.state.startedAt != nil }
        listening.cancel()

        // Without the retry the screen sat on « Disponible : oui » next to
        // « Écoute depuis : flux non ouvert » for as long as it was left open,
        // and only a close-and-reopen — on a wrist, outdoors, mid-outing —
        // would have unstuck it.
        #expect(motion.opens == 1)
        #expect(value(of: "Disponible", in: probe.state, now: base) == "oui")
        #expect(value(of: "Écoute depuis", in: probe.state, now: base) != "flux non ouvert")
    }

    @Test("Retrying every tick opens the stream once, not once a second")
    func theRetryIsIdempotent() async {
        let motion = FakeMotion()
        motion.isAvailable = true
        let probe = WatchMotionProbe(engine: motion.engine)

        let listening = Task { await probe.keepListening(interval: .milliseconds(10)) }
        // Long enough for many ticks; the assertion is on the count, not the
        // clock, so a slow machine only makes it stronger.
        await waitUntil { motion.reads >= 5 }
        listening.cancel()

        #expect(motion.opens == 1)
        #expect(motion.closes == 0)
    }

    @Test("An unavailable device is never asked for a stream")
    func anUnavailableDeviceIsLeftAlone() async {
        let motion = FakeMotion()
        let probe = WatchMotionProbe(engine: motion.engine)

        let listening = Task { await probe.keepListening(interval: .milliseconds(10)) }
        await waitUntil { motion.reads >= 5 }
        listening.cancel()

        // `startActivityUpdates` is documented as undefined when activity data
        // is unavailable, and the retry must not turn that into a crash on a
        // wrist. The screen says « Disponible : non », which is the answer.
        #expect(motion.opens == 0)
        #expect(value(of: "Disponible", in: probe.state, now: base) == "non")
        #expect(value(of: "Écoute depuis", in: probe.state, now: base) == "flux non ouvert")
    }

    // MARK: - The readings describe the window they are shown next to

    @Test("Reopening the screen counts the new window, not the old one")
    func aReopenedWindowStartsFromZero() async {
        let motion = FakeMotion()
        motion.isAvailable = true
        let probe = WatchMotionProbe(engine: motion.engine)

        probe.start(now: base)
        motion.deliver(estimate(at: base))
        motion.deliver(estimate(at: base))
        // The count carried over only matters if it really existed.
        await waitUntil { probe.state.estimateCount == 2 }
        probe.stop()

        // Two minutes later the owner reopens « Diagnostic », and reads it one
        // minute after that.
        probe.start(now: base.addingTimeInterval(120))
        let now = base.addingTimeInterval(180)

        // Before the fix this read « 2 estimations » next to « il y a 1 min
        // 00 s » of listening — a stream that had delivered nothing in that
        // window looking exactly like a healthy one.
        #expect(value(of: "Écoute depuis", in: probe.state, now: now) == "il y a 1 min 00 s")
        #expect(value(of: "Estimations reçues", in: probe.state, now: now) == "0")
        #expect(value(of: "Dernière reçue", in: probe.state, now: now) == "aucune")
    }

    @Test("What the new window receives is what it counts")
    func theNewWindowCountsItsOwnEstimates() async {
        let motion = FakeMotion()
        motion.isAvailable = true
        let probe = WatchMotionProbe(engine: motion.engine)

        probe.start(now: base)
        motion.deliver(estimate(at: base))
        await waitUntil { probe.state.estimateCount == 1 }
        probe.stop()
        probe.start(now: base.addingTimeInterval(120))
        motion.deliver(estimate(at: base.addingTimeInterval(150), walking: false))
        await waitUntil { probe.state.estimateCount == 1 }
        let now = base.addingTimeInterval(180)

        #expect(value(of: "Dernière reçue", in: probe.state, now: now) == "il y a 30 s")
        // …and the flags follow the new estimate, not the one from last time.
        #expect(value(of: "marche", in: probe.state, now: now) == "non")
    }

    @Test("Closing the screen takes the listening clock with it")
    func closingClearsTheWindow() async {
        let motion = FakeMotion()
        motion.isAvailable = true
        let probe = WatchMotionProbe(engine: motion.engine)

        probe.start(now: base)
        motion.deliver(estimate(at: base))
        await waitUntil { probe.state.latest != nil }
        probe.stop()

        #expect(motion.closes == 1)
        // A `startedAt` that outlives its stream is the same lie as the count:
        // it would put « Écoute depuis : il y a 12 min » on the first frame of
        // a reopen, before anything is listening again.
        #expect(probe.state.startedAt == nil)
        #expect(value(of: "Écoute depuis", in: probe.state, now: base) == "flux non ouvert")
    }

    // MARK: - Helpers

    /// Poll until `condition` holds, up to four seconds. A fixed sleep is what
    /// makes a suite flaky; this one returns as soon as the behaviour appears
    /// and only spends the full budget when it never does.
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<400 {
            if condition() { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
