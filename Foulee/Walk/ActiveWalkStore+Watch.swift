import CoreLocation
import Foundation

/// The phone's session, shown and steered from the wrist (issue #342).
///
/// The phone stays the only recorder — one session, one workout in Santé. The
/// wrist is told the session's state and sends commands back; nothing here
/// waits for it.
extension ActiveWalkStore {
    /// How often a session in flight is retold while nothing else changes.
    /// The clock runs on its own at the wrist from `timerBasis`; this only
    /// carries the counters and the route.
    static let watchInterval: TimeInterval = 3

    /// The session in flight, for a command that arrives from the wrist.
    ///
    /// The store belongs to the screen that shows it; a message from the watch
    /// lands in `PhoneWatchSync`, which has no screen. Weak, so a closed
    /// screen leaves nothing behind to steer.
    private(set) static weak var current: ActiveWalkStore?

    /// Tell the wrist where the session stands — now, whatever the interval.
    /// Called at every change of phase.
    ///
    /// Back to idle, a store withdraws what it told — and only a store that
    /// told something: a screen opened and closed without a walk has nothing
    /// to take back.
    func tellWatch() {
        guard case .idle = state else {
            Self.current = self
            lastWatchUpdateAt = date.now
            watchLive.publish(watchSnapshot(at: date.now))
            return
        }
        guard lastWatchUpdateAt != nil else { return }
        if Self.current === self { Self.current = nil }
        lastWatchUpdateAt = nil
        watchLive.publish(nil)
    }

    /// Retell a session in flight once `watchInterval` has passed. Called on
    /// every tick of the clock.
    func tellWatchIfDue() {
        if let last = lastWatchUpdateAt, date.now.timeIntervalSince(last) < Self.watchInterval { return }
        tellWatch()
    }

    /// The session as the wrist shows it, or `nil` when there is none.
    func watchSnapshot(at now: Date) -> PhoneSessionSnapshot? {
        let session: WalkSession
        let phase: PhoneSessionSnapshot.Phase
        switch state {
        case .idle:
            return nil
        case .active(let live):
            session = live
            phase = .active
        case .paused(let held):
            session = held
            phase = .paused
        case .finished(let done):
            session = done
            phase = .ended
        }
        return PhoneSessionSnapshot(
            sentAt: now,
            activity: session.activity,
            phase: phase,
            elapsed: session.elapsed,
            steps: session.steps,
            distanceMeters: session.distanceMeters,
            activeCalories: session.estimatedCalories,
            route: phase == .ended ? [] : MirroredRoutePortion.thinning(
                [(activity: session.activity, points: route.map(\.locationCoordinate))]
            )
        )
    }

    /// Carry out what the wrist asked. `false` when the session is not in a
    /// state to obey — it ended, or was already paused a second before.
    func perform(_ command: PhoneSessionCommand) async -> Bool {
        switch (command, state) {
        case (.pause, .active):
            await pause()
        case (.resume, .paused):
            resume()
        case (.stop, .active), (.stop, .paused):
            await stop()
        default:
            return false
        }
        return true
    }
}
