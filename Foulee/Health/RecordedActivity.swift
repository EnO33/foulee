import Foundation

/// What a session already in Santé *was* — the read-side counterpart of
/// `SessionActivity` (issue #245).
///
/// Wider than `SessionActivity` on purpose, and the two must not be merged.
/// `SessionActivity` is what Foulée is allowed to **write**: two cases, because
/// every session it records is one or the other and that stamp is permanent.
/// This one names what comes **back**, and the résumé reads whatever
/// `WorkoutActivityFilter` accepts — hiking included since #217 — plus whatever
/// a future widening lets through.
///
/// It exists because until now no surface of Foulée showed the type of a past
/// session. A mis-stamped session — by the picker, or by the watch's automatic
/// detection since #249 — was visible **only in Santé**, and `HKWorkout` is
/// immutable: the app has no delete path, so the mistake was permanent and
/// unnoticeable at once. Showing the type fixes nothing by itself; it turns an
/// invisible error into a *noticeable* one, which the owner can then correct by
/// hand in Santé.
enum RecordedActivity: String, Equatable, Hashable, Sendable, CaseIterable {
    case walking
    case running
    case hiking
    /// A type Foulée cannot name.
    ///
    /// Unreachable through today's filter, which accepts exactly the three
    /// above — and kept anyway, because it is also the **default** for a
    /// `WorkoutSummary` built without one. That default is the whole point:
    /// defaulting to `.walking` would have every forgotten call site claim a
    /// walk, which is precisely the failure issue #223 spent a release
    /// undoing. « Séance » is the honest answer to a question nobody answered.
    case other

    /// How the résumé and the detail name it, in the vocabulary established by
    /// #222: the same « Marche » and « Course » the pickers use.
    var label: String {
        switch self {
        case .walking: "Marche"
        case .running: "Course"
        case .hiking: "Randonnée"
        case .other: "Séance"
        }
    }

    /// The figure drawn next to it.
    ///
    /// `.other` keeps the neutral walk-and-run glyph the two screens used for
    /// every row before this issue — the right drawing for « we were not told ».
    var icon: String {
        switch self {
        case .walking: ActivityGlyph.walk
        case .running: ActivityGlyph.run
        case .hiking: ActivityGlyph.hike
        case .other: ActivityGlyph.mixedCardio
        }
    }
}
