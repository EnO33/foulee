import os
@preconcurrency import HealthKit

/// Nothing is mirroring, so there is nobody to ask (issue #282). Ordinary, not
/// exceptional: the wrist may have stopped a second before the tap landed.
enum MirrorSendError: Error {
    case noSession
}

/// The real mirror, backed by `HKHealthStore.workoutSessionMirroringStartHandler`.
///
/// ⚠️ **None of this file runs in a simulator.** Mirroring needs a real watch
/// paired to a real phone, so nothing here is exercised by CI or by any test —
/// only `MirroredSessionStore`, which consumes the stream, is. That is why
/// every branch below logs: the first outing on a wrist is the test, and it has
/// to leave a trace whichever way it goes.
extension MirroredWorkoutClient {
    static let liveValue: MirroredWorkoutClient = {
        let store = HKHealthStore()
        // Shared by both closures: `send` has to reach the very session
        // `events` adopted, and a bridge per stream would leave the sender
        // talking to nothing.
        let bridge = MirrorBridge()
        return MirroredWorkoutClient(
            events: {
                AsyncStream { continuation in
                    bridge.attach(continuation)
                    store.workoutSessionMirroringStartHandler = { session in
                        bridge.adopt(session)
                    }
                    continuation.onTermination = { _ in
                        // The handler is a single slot, not a subscriber list —
                        // leaving a dead closure in it would silently swallow
                        // the next mirror.
                        store.workoutSessionMirroringStartHandler = nil
                        bridge.detach()
                    }
                }
            },
            send: { command in try await bridge.send(command) }
        )
    }()
}

/// Holds the mirrored session alive and turns its delegate callbacks into
/// stream events.
///
/// A class because `HKWorkoutSession.delegate` is **weak** and the session
/// handed to the handler is otherwise unowned: dropping it would end the mirror
/// the instant the handler returned.
private final class MirrorBridge: NSObject, HKWorkoutSessionDelegate, @unchecked Sendable {
    private let stream = OSAllocatedUnfairLock<AsyncStream<MirroredSessionEvent>.Continuation?>(
        initialState: nil
    )
    /// The mirror in flight. Replaced rather than accumulated: a change of
    /// sport closes one session and opens another (issue #265), so the phone
    /// sees a *new* mirror at each switch and only the newest is current.
    private let current = OSAllocatedUnfairLock<HKWorkoutSession?>(initialState: nil)

    func attach(_ continuation: AsyncStream<MirroredSessionEvent>.Continuation) {
        stream.withLock { $0 = continuation }
    }

    func detach() {
        stream.withLock { $0 = nil }
        current.withLock { $0 = nil }
    }

    /// Ask the wrist to do something (issue #282).
    ///
    /// Throws `MirrorSendError.noSession` when nothing is mirroring, which is
    /// the ordinary case rather than a failure — the caller turns it into « la
    /// séance n'est plus là » rather than an error banner.
    func send(_ command: MirrorCommand) async throws {
        guard let session = current.withLock({ $0 }) else { throw MirrorSendError.noSession }
        try await session.sendToRemoteWorkoutSession(data: JSONEncoder().encode(command))
    }

    private func yield(_ event: MirroredSessionEvent) {
        stream.withLock { $0 }?.yield(event)
    }

    func adopt(_ session: HKWorkoutSession) {
        current.withLock { $0 = session }
        session.delegate = self
        let activity = SessionActivity(session.workoutConfiguration.activityType)
        FouleeLog.session.notice(
            "miroir reçu de la Watch : \(activity?.label ?? "sport inconnu", privacy: .public)"
        )
        yield(
            .started(
                MirroredSession(
                    // `startDate` is nil until the session has actually begun;
                    // the wearer is already walking by the time we hear about
                    // it, so `.now` is the honest fallback rather than a zero.
                    startedAt: session.startDate ?? .now,
                    // An unknown sport is still a session — it is named
                    // « Séance » on screen rather than dropped.
                    activity: activity ?? .walking
                )
            )
        )
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended else { return }
        // Only the mirror we are currently showing may end the display. A leg
        // closed by a change of sport ends too, a moment after its successor
        // opened — the same trap issue #290 fell into on the wrist.
        let isCurrent = current.withLock { $0 === workoutSession }
        guard isCurrent else {
            FouleeLog.session.notice("fin de miroir ignorée, jambe déjà remplacée")
            return
        }
        FouleeLog.session.notice("miroir terminé")
        yield(.ended)
    }

    /// Figures pushed by the wrist (issue #278).
    ///
    /// **An array**, not one payload: HealthKit caches what a mirrored session
    /// sends and hands over everything that accumulated since the last wake, so
    /// a single delivery routinely carries several minutes of snapshots. Each is
    /// a complete state, so they can simply all be yielded — the store keeps the
    /// newest by `sentAt` and drops the rest.
    ///
    /// Not filtered by session on purpose, unlike the state callbacks. A leg
    /// that was replaced a second ago may still deliver figures that are the
    /// freshest the phone has, and `sentAt` already decides which wins.
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        let decoder = JSONDecoder()
        for payload in data {
            guard let snapshot = try? decoder.decode(WatchSessionSnapshot.self, from: payload) else {
                // A payload from a build this one does not understand. The
                // decoder is written to degrade rather than throw, so reaching
                // here means something worse than a new field.
                FouleeLog.session.error("snapshot illisible reçu de la Watch")
                continue
            }
            yield(.snapshot(snapshot))
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        FouleeLog.session.error(
            "miroir en échec : \(error.localizedDescription, privacy: .public)"
        )
        let isCurrent = current.withLock { $0 === workoutSession }
        guard isCurrent else { return }
        yield(.ended)
    }
}
