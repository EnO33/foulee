import Foundation

/// A clock that moves only when the test says so (issue #406).
///
/// `WatchWorkoutStore` dates every pause, leg and batch with the clock it is
/// given. Handing it this one makes a test's arithmetic exact: no bracket
/// around `start`, no tolerance for a slow runner.
@MainActor
final class ManualClock {
    /// Where every clock starts: the `base` the store suites date their
    /// estimates and splits from.
    nonisolated static let origin = Date(timeIntervalSince1970: 1_754_000_000)

    private(set) var now = ManualClock.origin

    func advance(by interval: TimeInterval) {
        now.addTimeInterval(interval)
    }

    var read: @MainActor () -> Date {
        { [self] in now }
    }
}
