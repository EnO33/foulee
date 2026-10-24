import Foundation

/// A notification to send for an outing that just landed (issue #529): what
/// the register decided, told by its highlight.
nonisolated public struct SessionNotice: Equatable, Sendable {
    public static let prefix = "foulee.session."

    /// Stable while the outing grows: a later notice for the same outing
    /// replaces the pending one.
    public var identifier: String
    public var fireAt: Date
    public var title: String
    public var body: String
    /// The outing announced, to open it on a tap.
    public var startedAt: Date
    public var endedAt: Date

    public init(identifier: String, fireAt: Date, title: String, body: String, startedAt: Date, endedAt: Date) {
        self.identifier = identifier
        self.fireAt = fireAt
        self.title = title
        self.body = body
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

nonisolated public extension SessionAnnouncements {
    /// The notices `workouts` call for at `now`, the register updated.
    ///
    /// Each one is measured against the same `workouts` it was found in, and
    /// avoids the angle of the outing announced before it.
    mutating func notices(
        for workouts: [WorkoutSummary],
        now: Date,
        calendar: Calendar = .iso8601Monday
    ) -> [SessionNotice] {
        announce(workouts, now: now).map { announcement in
            let benchmark = SessionBenchmark.make(for: announcement.outing, among: workouts, calendar: calendar)
            let highlight = SessionHighlight.pick(for: benchmark, avoiding: angle(before: announcement.id))
            record(highlight.angle, for: announcement.id)
            return SessionNotice(
                identifier: SessionNotice.prefix + announcement.id.uuidString,
                fireAt: announcement.fireAt,
                title: highlight.title,
                body: highlight.body,
                startedAt: announcement.outing.startedAt,
                endedAt: announcement.outing.endedAt
            )
        }
    }
}
