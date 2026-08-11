@preconcurrency import HealthKit

/// Which leg is which.
///
/// Two questions that have nothing to do with the state machine: what HealthKit
/// stamps a leg with, and whether a callback is about the leg in flight.
///
/// The second one is the whole of issue #290. Since issue #265 an outing opens
/// one session per leg and the store is the delegate of every one of them, so
/// « which leg is this about? » has to be asked on each callback. It was not,
/// and the answer was assumed to be « the current one » — false for exactly as
/// long as a closed session takes to finish dying, which is the window a switch
/// lives in. A real sortie ended there.
extension WatchWorkoutStore {
    /// The configuration HealthKit stamps a session — or one of its nested
    /// activities — with.
    ///
    /// One builder for both, because a nested activity of the same kind must be
    /// configured exactly like the session that would have started as it:
    /// `locationType` drifting between the two would make the same walk measure
    /// differently depending on whether it was chosen or detected.
    static func configuration(for activity: SessionActivity) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity.hkActivityType
        configuration.locationType = .outdoor
        return configuration
    }

    /// Offer the leg to the paired iPhone, and never lose a sortie over it
    /// (issue #277).
    ///
    /// **Deliberately swallowed, deliberately logged.** Mirroring is what lets
    /// the phone show the outing; it is not what records it. A phone that is
    /// off, unpaired, out of range or simply refusing has no business ending a
    /// walk that the wrist is measuring perfectly well.
    ///
    /// The log line is the point. Nothing about this path can be exercised in a
    /// simulator — `HKWorkoutSession` needs a real watch — so the first outing
    /// on a wrist is the test, and it has to leave a trace either way.
    func offerMirror(_ handle: WatchWorkoutSessionHandle) async {
        do {
            try await handle.startMirroring()
            FouleeLog.session.notice("miroir offert à l'iPhone")
        } catch {
            FouleeLog.session.error(
                "miroir refusé : \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Whether a HealthKit callback concerns the leg in flight (issue #290).
    ///
    /// `nil` is accepted: it means the caller had no session to name, which is
    /// how a test drives these paths and how a failure belonging to no session
    /// at all still reaches the screen.
    func isCurrentLeg(session id: ObjectIdentifier?) -> Bool {
        guard let id else { return true }
        return id == sessionHandle?.sessionID
    }

    /// The builder is a different object from its session, so a different
    /// identity — and the metrics path needs filtering just as much as the
    /// failure path does.
    func isCurrentLeg(builder id: ObjectIdentifier?) -> Bool {
        guard let id else { return true }
        return id == sessionHandle?.builderID
    }
}
