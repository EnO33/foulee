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

    /// The last figures the wrist stated (issue #278).
    ///
    /// `nil` while the phone knows a session is running but has not been told
    /// any numbers yet — which is a real state, not a transient one: HealthKit
    /// may take minutes to deliver the first batch. The screen says « en
    /// attente » rather than drawing zeros that look measured.
    private(set) var figures: WatchSessionSnapshot?

    /// The newest `sentAt` ever seen, kept **across outings**.
    ///
    /// Separate from `figures` because the two have different lifetimes, and
    /// conflating them was a real bug: clearing the figures at the end of an
    /// outing also cleared the high-water mark, so the first stale snapshot to
    /// arrive afterwards — and HealthKit delivers in *batches*, so there are
    /// usually several in flight — would be accepted and put a finished session
    /// back on screen.
    ///
    /// Never reset. A later outing sends later dates by construction, so a
    /// monotonic bound costs nothing and cannot lock anything out.
    @ObservationIgnored private var newestSentAt: Date?

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
        case .snapshot(let snapshot):
            apply(snapshot)
        case .ended:
            clear()
        }
    }

    /// Newest wins, and the outing's own clock comes from the wrist rather than
    /// from the leg the phone happens to be mirroring.
    ///
    /// Out-of-order arrivals are ordinary here: HealthKit hands over everything
    /// that accumulated since the last wake, and promises delivery rather than
    /// sequence. Comparing `sentAt` is what keeps a stale batch from rewinding
    /// the counters on screen.
    private func apply(_ snapshot: WatchSessionSnapshot) {
        if let newest = newestSentAt, newest >= snapshot.sentAt { return }
        newestSentAt = snapshot.sentAt
        figures = snapshot
        outingStartedAt = snapshot.outingStartedAt
        // Figures can arrive before — or instead of — the mirror that should
        // have announced the session. Believing them is better than showing
        // nothing while the wrist is plainly recording.
        if session == nil, !snapshot.isEnded {
            session = MirroredSession(
                startedAt: snapshot.outingStartedAt,
                activity: snapshot.activity
            )
        }
        session?.activity = snapshot.activity
        // The wrist saying so is the end. The alternative — an
        // `HKWorkoutType` observer in `.immediate` — fires on every
        // `finishWorkout()` since issue #265, so it would announce the end of
        // the outing at the first walk→run switch.
        if snapshot.isEnded { clear() }
    }

    private func clear() {
        session = nil
        outingStartedAt = nil
        figures = nil
    }

    /// Whether the wrist is recording something right now.
    var isMirroring: Bool { session != nil }

    /// Ask the wrist to end the outing (issue #282).
    ///
    /// **Nothing is changed here.** The phone does not end anything — it asks,
    /// and the watch's own `stop()` does the closing, the folding, the saving
    /// and the « Réessayer ». The display goes away when the wrist says the
    /// outing is over, not when the button is tapped, because until then it
    /// is not over.
    ///
    /// A refusal is ordinary rather than exceptional: the wrist may have
    /// stopped a second before the tap landed. Logged, not surfaced.
    func requestStop() async {
        do {
            try await client.send(.stop)
            FouleeLog.session.notice("arrêt demandé à la Watch")
        } catch {
            FouleeLog.session.notice(
                "arrêt non transmis : \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
