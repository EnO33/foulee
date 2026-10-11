#if DEBUG
import Foundation
import os

/// The clock the capture mode installs as `@Dependency(\.date)`.
///
/// Frozen at `ScreenshotSeed.instant`, with exactly one permitted move: the
/// session double advances it to a **fixed** offset so the running-session
/// screen shows a real duration instead of `00:00`. `ActiveWalkStore` computes
/// the elapsed time as `date.now - segmentStart`, so with a clock that never
/// moves the timer would read zero — and a clock that followed real time would
/// make the capture depend on how fast the UI test tapped.
///
/// `advance(toOffset:)` takes the maximum rather than adding, so calling it
/// once or a hundred times (the pedometer stream re-yields until cancelled)
/// produces the same instant. That idempotence is what keeps the capture
/// byte-identical from run to run.
final class ScreenshotClock: Sendable {
    static let shared = ScreenshotClock()

    /// Checked rather than `@unchecked` (issue #405): the lock owns the only
    /// mutable state, so the compiler can see the class is safe to share.
    private let offset = OSAllocatedUnfairLock<TimeInterval>(initialState: 0)

    private init() {}

    var now: Date {
        ScreenshotSeed.instant.addingTimeInterval(offset.withLock { $0 })
    }

    func advance(toOffset newOffset: TimeInterval) {
        offset.withLock { $0 = max($0, newOffset) }
    }
}
#endif
