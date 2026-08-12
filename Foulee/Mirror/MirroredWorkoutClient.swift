import Dependencies
import Foundation

/// The phone's half of workout-session mirroring (issue #277), as an injectable
/// struct-of-closures.
///
/// One closure, because there is only one thing the phone can do here: listen.
/// It does not own the session, cannot start one, and — until issue #282 —
/// cannot stop one either.
struct MirroredWorkoutClient: Sendable {
    /// Every mirror the Watch offers, and every one that closes.
    ///
    /// Consuming this **registers `workoutSessionMirroringStartHandler`**, and
    /// that has to happen at *process* start rather than when a screen appears:
    /// HealthKit can relaunch a terminated app to deliver a mirror, and on that
    /// path no UI is ever mounted. Same reason `startGarminConnectIQOnce`
    /// exists in `FouleeApp`.
    var events: @Sendable () -> AsyncStream<MirroredSessionEvent>
    /// Ask the wrist to do something (issue #282). Throws when there is no
    /// mirrored session to ask — the ordinary case when nothing is running.
    var send: @Sendable (MirrorCommand) async throws -> Void
}

extension MirroredWorkoutClient: DependencyKey {
    /// Nothing, and never anything. A preview has no paired watch, and a mirror
    /// that arrived out of nowhere would be a screen no user could reach.
    static let previewValue = MirroredWorkoutClient(
        events: { AsyncStream { $0.finish() } },
        send: { _ in }
    )

    static let testValue = MirroredWorkoutClient(
        events: { AsyncStream { $0.finish() } },
        send: { _ in }
    )
}

extension DependencyValues {
    var mirroredWorkout: MirroredWorkoutClient {
        get { self[MirroredWorkoutClient.self] }
        set { self[MirroredWorkoutClient.self] = newValue }
    }
}
