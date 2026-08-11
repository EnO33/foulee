import os
@preconcurrency import HealthKit

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
        return MirroredWorkoutClient(events: {
            AsyncStream { continuation in
                let bridge = MirrorBridge(continuation: continuation)
                store.workoutSessionMirroringStartHandler = { session in
                    bridge.adopt(session)
                }
                continuation.onTermination = { _ in
                    // The handler is a single slot, not a subscriber list —
                    // leaving a dead closure in it would silently swallow the
                    // next mirror.
                    store.workoutSessionMirroringStartHandler = nil
                    bridge.release()
                }
            }
        })
    }()
}

/// Holds the mirrored session alive and turns its delegate callbacks into
/// stream events.
///
/// A class because `HKWorkoutSession.delegate` is **weak** and the session
/// handed to the handler is otherwise unowned: dropping it would end the mirror
/// the instant the handler returned.
private final class MirrorBridge: NSObject, HKWorkoutSessionDelegate, @unchecked Sendable {
    private let continuation: AsyncStream<MirroredSessionEvent>.Continuation
    /// The mirror in flight. Replaced rather than accumulated: a change of
    /// sport closes one session and opens another (issue #265), so the phone
    /// sees a *new* mirror at each switch and only the newest is current.
    private let current = OSAllocatedUnfairLock<HKWorkoutSession?>(initialState: nil)

    init(continuation: AsyncStream<MirroredSessionEvent>.Continuation) {
        self.continuation = continuation
        super.init()
    }

    func adopt(_ session: HKWorkoutSession) {
        current.withLock { $0 = session }
        session.delegate = self
        let activity = SessionActivity(session.workoutConfiguration.activityType)
        FouleeLog.session.notice(
            "miroir reçu de la Watch : \(activity?.label ?? "sport inconnu", privacy: .public)"
        )
        continuation.yield(
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

    func release() {
        current.withLock { $0 = nil }
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
        continuation.yield(.ended)
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        FouleeLog.session.error(
            "miroir en échec : \(error.localizedDescription, privacy: .public)"
        )
        let isCurrent = current.withLock { $0 === workoutSession }
        guard isCurrent else { return }
        continuation.yield(.ended)
    }
}
