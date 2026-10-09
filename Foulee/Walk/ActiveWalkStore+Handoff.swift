import Foundation

/// Carrying a phone walk on at the wrist (issue #335).
///
/// There is no API to move a workout session from the phone to the watch, so
/// the walk is **cut**, not moved: the phone saves what it measured as the
/// outing's leg 0, and the wrist opens leg 1 of the same outing. `OutingLeg`
/// ties the two workouts back into one row of the history (ADR 0003).
///
/// Two doors, one mechanism: the phone's « Continuer sur ma Watch »
/// (`handOffToWatch`) and the wrist's « Reprendre la séance de l'iPhone »,
/// which reaches `handOff` through `PhoneWatchSync` with the app in the
/// background.
extension ActiveWalkStore {
    /// The walk in flight, for a request that arrives from the wrist.
    ///
    /// The store belongs to the screen that shows it; a message from the watch
    /// lands in `PhoneWatchSync`, which has no screen. Weak, so a closed
    /// screen leaves nothing behind to hand over.
    private(set) static weak var current: ActiveWalkStore?

    /// Stop measuring, save this walk as the outing's first leg, and return
    /// what the wrist needs to carry it on. `nil` when there is no walk.
    ///
    /// Returns the handoff even if the save failed: the outing still goes on
    /// at the wrist, and the failure is in `lastError` like any other.
    func handOff() async -> SessionHandoff? {
        switch state {
        case .active, .paused: break
        default: return nil
        }
        let outing = OutingLeg(outingID: UUID(), index: 0)
        await stop(as: outing)
        guard case .finished(let walk) = state, let end = walk.endedAt else { return nil }
        if let lastError {
            FouleeLog.session.error("reprise : portion iPhone non enregistrée : \(lastError, privacy: .public)")
        }
        return SessionHandoff(
            outingID: outing.outingID,
            phoneLeg: SessionHandoff.Leg(
                activity: walk.activity,
                start: walk.startedAt,
                end: end,
                steps: walk.steps,
                distanceMeters: walk.distanceMeters,
                activeCalories: walk.estimatedCalories
            )
        )
    }

    /// « Continuer sur ma Watch »: hand the walk over, then wake the watch app
    /// to take it up.
    ///
    /// The handoff goes out **before** the watch is woken, in the application
    /// context the watch reads as soon as it listens; `startWatchApp` only
    /// carries a sport. When the wrist opens its leg it mirrors it back, and the
    /// home swaps this screen for the mirrored one, as it already does for any
    /// outing started at the wrist.
    func handOffToWatch() async {
        guard let handoff = await handOff() else { return }
        watchHandoff.publishHandoff(handoff)
        do {
            try await mirroredWorkout.startWatchSession(handoff.phoneLeg.activity)
            FouleeLog.session.notice("reprise confiée à la Watch")
        } catch {
            // The phone's leg is saved either way; this is the wrist not
            // answering. Said on screen, not only in the log.
            lastError = "La Watch n'a pas pu reprendre la séance."
            FouleeLog.session.error(
                "reprise refusée par la Watch : \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Tell the wrist a walk is in progress, so it can offer to take it over.
    func announceToWatch(_ session: WalkSession) {
        Self.current = self
        watchHandoff.publishPhoneSession(PhoneSessionStatus(startedAt: session.startedAt))
    }

    /// The walk is over, here or handed over: nothing left to offer.
    func withdrawFromWatch() {
        guard Self.current === self else { return }
        Self.current = nil
        watchHandoff.publishPhoneSession(nil)
    }
}
