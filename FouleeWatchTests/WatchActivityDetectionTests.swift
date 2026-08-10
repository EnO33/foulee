import Foundation
import Testing
@testable import FouleeWatch

/// The lifetime half of issue #249: when the motion stream opens, when it
/// closes, and what happens when the device is not ready at the instant a
/// session starts.
///
/// The decision half is `WatchActivitySwitchTests`, and it is pure. This is the
/// part that is not, and the part no simulator can drive through real CoreMotion
/// — `CMMotionActivityManager.isActivityAvailable()` is false on all of them.
/// Its failure mode is also the quietest one in the feature: detection that
/// never runs for a whole outing, with nothing on screen to say so.
@Suite("Watch activity detection stream")
@MainActor
struct WatchActivityDetectionTests {
    /// Escaping-closure output, collected somewhere a test can read it.
    @MainActor
    final class SwitchLog {
        private(set) var switches: [ActivitySwitchDetector.Switch] = []
        func record(_ confirmed: ActivitySwitchDetector.Switch) { switches.append(confirmed) }
    }

    private let base = Date(timeIntervalSince1970: 1_754_000_000)

    private func running(at offset: TimeInterval) -> MotionActivityEstimate {
        motionEstimate(startDate: base.addingTimeInterval(offset), running: true)
    }

    @Test("A capability that resolves after the session started still opens the stream")
    func lateAvailabilityStillOpensTheStream() async {
        let motion = FakeMotionSource()
        // Unavailable on the first two reads, available afterwards.
        motion.becomesAvailableOnRead = 3
        let detection = WatchActivityDetection(source: motion.source)

        detection.start(from: .walking, at: base, retryInterval: .milliseconds(10)) { _ in }
        await waitUntil { motion.isStreaming }

        // A single attempt at session start would have left detection off for
        // the whole outing, and unlike the probe of issue #248 there is no
        // screen saying « flux non ouvert » to notice it by.
        #expect(motion.opens == 1)
    }

    @Test("An unavailable device is never asked for a stream, and not forever either")
    func anUnavailableDeviceIsLeftAlone() async {
        let motion = FakeMotionSource()
        let detection = WatchActivityDetection(source: motion.source)

        detection.start(
            from: .walking,
            at: base,
            retryInterval: .milliseconds(10),
            maximumAttempts: 3
        ) { _ in }
        await waitUntil { motion.reads >= 3 }
        // `startActivityUpdates` is documented as undefined when activity data
        // is unavailable, and a crash here happens on a wrist, mid-outing.
        #expect(motion.opens == 0)

        // And the retry gives up: availability is a property of the hardware,
        // so a loop that kept asking would tick for the whole hour a session
        // lasts, learning nothing.
        try? await Task.sleep(for: .milliseconds(120))
        #expect(motion.reads == 3)
    }

    @Test("A confirmed switch reaches the caller, once")
    func aConfirmedSwitchIsReported() async {
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let detection = WatchActivityDetection(source: motion.source)
        let log = SwitchLog()

        detection.start(from: .walking, at: base, retryInterval: .milliseconds(10)) { log.record($0) }
        await waitUntil { motion.isStreaming }
        motion.deliver(running(at: 60))
        motion.deliver(running(at: 90))
        await waitUntil { log.switches.count == 1 }

        #expect(log.switches.first?.activity == .running)
        #expect(log.switches.first?.date == base.addingTimeInterval(60))
    }

    @Test("Stopping closes the stream")
    func stoppingClosesTheStream() async {
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let detection = WatchActivityDetection(source: motion.source)

        detection.start(from: .walking, at: base, retryInterval: .milliseconds(10)) { _ in }
        await waitUntil { motion.isStreaming }
        detection.stop()

        #expect(motion.closes == 1)
        // Not just "closed": nothing is listening any more, so a late estimate
        // has nowhere to land. A stream left open past the session is a
        // background CoreMotion subscription nobody ever turns off.
        #expect(!motion.isStreaming)
    }

    @Test("Starting twice leaves one stream, not two")
    func startingTwiceDoesNotStackStreams() async {
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let detection = WatchActivityDetection(source: motion.source)

        detection.start(from: .walking, at: base, retryInterval: .milliseconds(10)) { _ in }
        await waitUntil { motion.isStreaming }
        detection.start(from: .running, at: base, retryInterval: .milliseconds(10)) { _ in }
        await waitUntil { motion.opens == 2 }

        #expect(motion.closes == 1)
        #expect(motion.opens == 2)
    }

    @Test("An estimate arriving before any session is ignored")
    func estimatesOutsideASessionChangeNothing() {
        let motion = FakeMotionSource()
        let detection = WatchActivityDetection(source: motion.source)
        // No detector, so nothing to decide with. Reaching for one anyway is
        // how a stop-then-late-callback turns into a switch on a dead session.
        detection.ingest(running(at: 60))
        detection.ingest(running(at: 90))
        #expect(motion.opens == 0)
    }
}
