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
    /// Wake the watch app and ask it to start a session (issue #283).
    ///
    /// The phone never measures it: `startWatchApp(with:)` hands a
    /// configuration to the wrist, which opens the session and mirrors it back.
    /// A remote control again, from the other end.
    var startWatchSession: @Sendable (SessionActivity) async throws -> Void
    /// Whether there is a watch app to wake at all.
    var isWatchAppInstalled: @Sendable () -> Bool
}

extension MirroredWorkoutClient: DependencyKey {
    /// Nothing, and never anything. A preview has no paired watch, and a mirror
    /// that arrived out of nowhere would be a screen no user could reach.
    static let previewValue = MirroredWorkoutClient(
        events: { AsyncStream { $0.finish() } },
        send: { _ in },
        startWatchSession: { _ in },
        isWatchAppInstalled: { false }
    )

    static let testValue = MirroredWorkoutClient(
        events: { AsyncStream { $0.finish() } },
        send: { _ in },
        startWatchSession: { _ in },
        isWatchAppInstalled: { false }
    )
}

extension DependencyValues {
    var mirroredWorkout: MirroredWorkoutClient {
        get { self[MirroredWorkoutClient.self] }
        set { self[MirroredWorkoutClient.self] = newValue }
    }
}
