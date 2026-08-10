import Foundation
import Testing
@testable import FouleeWatch

/// A CoreMotion that does what the test says, including changing its mind.
///
/// Shared by every suite that needs one, because there is exactly one thing
/// worth faking here and two copies of it would drift. It exists at all for a
/// hard reason: `CMMotionActivityManager.isActivityAvailable()` is `false` on
/// every simulator, so through real CoreMotion neither the probe's retry (issue
/// #248) nor the live detection (issue #249) is reachable at all off a wrist.
@MainActor
final class FakeMotionSource {
    var isAvailable = false
    /// Flips availability on once this many reads have happened — a device
    /// whose capability only resolves after listening has already started.
    var becomesAvailableOnRead: Int?

    private(set) var reads = 0
    private(set) var opens = 0
    private(set) var closes = 0
    private var handler: (@Sendable (MotionActivityEstimate) -> Void)?

    var source: MotionActivitySource {
        MotionActivitySource(
            isAvailable: { [self] in
                reads += 1
                if let threshold = becomesAvailableOnRead, reads >= threshold { isAvailable = true }
                return isAvailable
            },
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
    func deliver(_ estimate: MotionActivityEstimate) {
        handler?(estimate)
    }

    /// Whether anything is listening. A stream the source has closed delivers
    /// nothing, which is the difference between "detection stopped" and
    /// "detection is still running and just happens to be quiet".
    var isStreaming: Bool { handler != nil }
}

/// One estimate, spelled out. Defaults describe a confident reading that
/// asserts nothing, so each test states only what it is actually about.
func motionEstimate(
    startDate: Date,
    receivedAt: Date? = nil,
    confidence: MotionActivityConfidence = .high,
    walking: Bool = false,
    running: Bool = false
) -> MotionActivityEstimate {
    MotionActivityEstimate(
        startDate: startDate,
        receivedAt: receivedAt ?? startDate,
        confidence: confidence,
        walking: walking,
        running: running
    )
}

extension MotionActivitySource {
    /// A device with no motion hardware at all: available to nobody, opening
    /// nothing.
    ///
    /// The default for suites that are not about detection. Without it they
    /// would build the real `.live()` source, which on a simulator answers
    /// « unavailable » anyway — but only after a background retry loop has
    /// woken up thirty times per test.
    static let inert = MotionActivitySource(
        isAvailable: { false },
        openStream: { _ in },
        closeStream: {}
    )
}

/// Poll until `condition` holds, up to four seconds. A fixed sleep is what
/// makes a suite flaky; this one returns as soon as the behaviour appears and
/// only spends the full budget when it never does.
@MainActor
func waitUntil(
    _ condition: @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    for _ in 0..<400 {
        if condition() { break }
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), sourceLocation: sourceLocation)
}
