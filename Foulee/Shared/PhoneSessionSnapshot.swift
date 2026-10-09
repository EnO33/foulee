import Foundation

/// The phone's session in flight, as the wrist shows it (issue #342).
///
/// The phone stays the only recorder: one session, one workout in Santé. The
/// watch only displays it and sends commands back — the mirror of what the
/// phone does for an outing started at the wrist (#279, #282, #334), carried
/// by WatchConnectivity because HealthKit mirrors watch → phone only.
///
/// Under ADR 0003 D2: **a complete, dated state, never a delta.** A message
/// lost on the way is corrected by the next one; the wrist keeps the newest by
/// `sentAt`.
struct PhoneSessionSnapshot: Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case active
        case paused
        /// The phone stopped. Sent once, so the wrist lets go at once rather
        /// than waiting for the session to go stale.
        case ended
    }

    var sentAt: Date
    var activity: SessionActivity
    var phase: Phase
    /// Elapsed time at `sentAt`, pauses excluded.
    var elapsed: TimeInterval
    var steps: Int
    var distanceMeters: Double
    var activeCalories: Int
    /// The phone's route so far, thinned (`MirroredRoutePortion.thinning`).
    var route: [MirroredRoutePortion] = []

    /// The instant the clock would have read zero, so the wrist runs it on its
    /// own between two deliveries. `nil` while paused: a frozen clock.
    var timerBasis: Date? {
        phase == .active ? sentAt.addingTimeInterval(-elapsed) : nil
    }
}

extension PhoneSessionSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case sentAt, activity, phase, elapsed, steps, distanceMeters, activeCalories, route
    }

    /// Tolerant, like every payload between the two apps, which update
    /// separately: an unknown sport reads as a walk, an unknown phase as
    /// active, a route this build cannot read as no route.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sentAt = try container.decode(Date.self, forKey: .sentAt)
        activity = (try? container.decode(SessionActivity.self, forKey: .activity)) ?? .walking
        phase = (try? container.decode(Phase.self, forKey: .phase)) ?? .active
        elapsed = try container.decodeIfPresent(TimeInterval.self, forKey: .elapsed) ?? 0
        steps = try container.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? 0
        activeCalories = try container.decodeIfPresent(Int.self, forKey: .activeCalories) ?? 0
        route = (try? container.decodeIfPresent([MirroredRoutePortion].self, forKey: .route)) ?? []
    }
}

/// What the wrist can ask of the phone's session (issue #342).
enum PhoneSessionCommand: String, Codable, Sendable {
    case pause
    case resume
    case stop
}

/// The WatchConnectivity keys of the phone's session (issue #342). One
/// spelling, read by both apps.
enum PhoneSessionKey {
    /// Application context and live message: the latest `PhoneSessionSnapshot`.
    /// Absent from the context when there is no session.
    static let snapshot = "phoneSession"
    /// Message from the wrist: a `PhoneSessionCommand`.
    static let command = "phoneSessionCommand"
    /// Reply to a command: whether the phone carried it out.
    static let done = "done"
}
