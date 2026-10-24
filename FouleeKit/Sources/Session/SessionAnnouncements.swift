import Foundation

/// The outings already announced, so each one is announced once (issue #528).
///
/// The same outing shows up again and again: every Health wake reads all the
/// recent workouts back; a watch outing lands leg by leg (#316); a Garmin
/// outing comes first from the watch, then again from Garmin Connect through
/// Santé (ADR 0009). An outing that overlaps or touches one of the register is
/// that one. Each entry keeps what its notification said, so the next one can
/// say something else.
///
/// **Sent a minute late.** A notification is scheduled `delay` after the
/// outing is seen, and replaced — same identifier — when a later leg extends
/// it in the meantime. Once it has gone, the outing is done with.
///
/// Persisted as JSON by the app; pure here.
nonisolated struct SessionAnnouncements: Codable, Equatable, Sendable {
    nonisolated struct Entry: Codable, Equatable, Sendable {
        /// The notification's identifier, kept while the outing grows.
        var id: UUID
        var start: Date
        var end: Date
        /// When its notification goes — or went.
        var fireAt: Date
        /// What its notification said, once decided.
        var angle: SessionHighlight.Angle?
    }

    /// A notification to schedule, or to replace when `id` is already
    /// pending.
    nonisolated struct Announcement: Equatable, Sendable {
        var id: UUID
        var outing: WorkoutSummary
        var fireAt: Date
    }

    /// Nothing that ended before is announced: turning the feature on — or
    /// installing the update that brings it — must not announce the day's
    /// earlier outings at once.
    var since: Date
    var entries: [Entry] = []

    /// The wait for the legs that follow.
    static let delay: TimeInterval = 60
    /// An outing that ended longer ago than this is old news.
    static let freshness: TimeInterval = 6 * 60 * 60
    /// How long an entry is kept: well past `freshness`, so a late copy of
    /// an announced outing still finds it.
    static let retention: TimeInterval = 7 * 24 * 60 * 60

    /// The notifications `workouts` call for at `now`, the register updated
    /// with them. `workouts` are Santé's as the résumé reads them: legs and
    /// copies are grouped here.
    mutating func announce(_ workouts: [WorkoutSummary], now: Date) -> [Announcement] {
        entries.removeAll { now.timeIntervalSince($0.end) > Self.retention }
        let outings = WorkoutDeduplication.collapsingOverlaps(OutingGrouping.groupingLegs(workouts))
            .filter { $0.endedAt >= since && now.timeIntervalSince($0.endedAt) <= Self.freshness }
            .sorted { $0.startedAt < $1.startedAt }
        return outings.compactMap { announce($0, now: now) }
    }

    /// The angle the notification `id` should avoid: that of the outing
    /// announced before it. Its own, when it replaces itself, is not one.
    func angle(before id: UUID) -> SessionHighlight.Angle? {
        entries.filter { $0.id != id && $0.angle != nil }.max { $0.fireAt < $1.fireAt }?.angle
    }

    /// Keeps what the notification `id` said, for the next one.
    mutating func record(_ angle: SessionHighlight.Angle, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].angle = angle
    }

    /// An outing already told some other way — recorded on this iPhone, its
    /// end screen in hand: on the register, never announced.
    mutating func markAnnounced(from start: Date, to end: Date) {
        entries.append(Entry(id: UUID(), start: start, end: end, fireAt: .distantPast))
    }

    private mutating func announce(_ outing: WorkoutSummary, now: Date) -> Announcement? {
        let fireAt = now.addingTimeInterval(Self.delay)
        guard let index = entries.firstIndex(where: { Self.isSame($0, outing) }) else {
            let entry = Entry(id: UUID(), start: outing.startedAt, end: outing.endedAt, fireAt: fireAt)
            entries.append(entry)
            return Announcement(id: entry.id, outing: outing, fireAt: fireAt)
        }
        guard now < entries[index].fireAt else { return nil }
        entries[index].start = min(entries[index].start, outing.startedAt)
        entries[index].end = max(entries[index].end, outing.endedAt)
        entries[index].fireAt = fireAt
        return Announcement(id: entries[index].id, outing: outing, fireAt: fireAt)
    }

    /// Overlapping, or touching within the tolerance legs are joined by.
    private static func isSame(_ entry: Entry, _ outing: WorkoutSummary) -> Bool {
        let tolerance = OutingGrouping.contiguityTolerance
        return entry.start <= outing.endedAt.addingTimeInterval(tolerance)
            && outing.startedAt <= entry.end.addingTimeInterval(tolerance)
    }
}
