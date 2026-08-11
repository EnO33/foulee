import Dependencies
import Foundation
import Observation

/// What the phone knows about the outing running on the wrist (issue #277).
///
/// A singleton, and observed at process start rather than when a screen
/// appears: HealthKit can relaunch a terminated app to deliver a mirror, and on
/// that path no UI is ever mounted. `FouleeApp.startMirrorObserverOnce` is what
/// starts it, for the same reason `startGarminConnectIQOnce` exists.
///
/// **This is the half that can be tested.** The stream it consumes comes from
/// `MirroredWorkoutClient`, which in production talks to a real watch and in a
/// test is whatever the test says — so every rule below (a switch of sport
/// replaces rather than stacks, an end clears, a late end after a new start is
/// not an end) is asserted, while the HealthKit wiring behind it is not and
/// cannot be.
@MainActor
@Observable
final class MirroredSessionStore {
    static let shared = MirroredSessionStore()

    /// The leg currently mirrored, or `nil` when the wrist is idle.
    private(set) var session: MirroredSession?

    /// When the **outing** began, across legs.
    ///
    /// Not `session.startedAt`. A change of sport closes one session and opens
    /// another (issue #265), so the mirrored leg's own start jumps forward mid
    /// outing — a clock built on it would reset to zero every time the wearer
    /// broke into a run. This is the first leg's start, kept until the wrist
    /// goes idle.
    private(set) var outingStartedAt: Date?

    @ObservationIgnored
    @Dependency(\.mirroredWorkout) private var client

    /// Consume the mirror stream until cancelled. One caller, at process start.
    func observe() async {
        for await event in client.events() {
            apply(event)
        }
    }

    /// Internal rather than private: it is the whole behaviour of this type,
    /// and driving it directly is what lets a test state the rules without
    /// standing up a stream.
    func apply(_ event: MirroredSessionEvent) {
        switch event {
        case .started(let mirrored):
            // The outing's clock survives the leg's. Only a mirror arriving
            // while the wrist was idle starts a new one.
            if outingStartedAt == nil { outingStartedAt = mirrored.startedAt }
            session = mirrored
        case .ended:
            session = nil
            outingStartedAt = nil
        }
    }

    /// Whether the wrist is recording something right now.
    var isMirroring: Bool { session != nil }
}
