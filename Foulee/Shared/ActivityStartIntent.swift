import Foundation

/// What a tap on « Démarrer » has to do, given the user's `ActivityMode`.
///
/// Replaces `SessionActivity.init(mode:)`, which used to answer the same
/// question with a `SessionActivity` and therefore *had* to invent something
/// for « les deux » — it returned `.walking`, and every session a "les deux"
/// user recorded went into Santé as a walk. `HKWorkout` is immutable, so that
/// stamp is permanent and no later fix reaches it (issue #223's premise, and
/// the whole reason #224 exists).
///
/// Two cases, and the second one carries no activity at all: the type is what
/// makes "we do not know yet" un-ignorable. A call site can no longer resolve
/// « les deux » by accident — it has to `switch`, and the `.ask` branch is
/// where the picker lives.
///
/// Shared with the watch target (see Project.swift): both platforms ask the
/// same question and both write their own workouts.
enum ActivityStartIntent: Equatable, Sendable {
    /// The mode already answers the question — start, one gesture, no picker.
    /// Asking here would be a regression for a user who has said « marche »
    /// or « course » once and for all.
    case start(SessionActivity)
    /// « Les deux »: ask before recording anything.
    case ask

    init(mode: ActivityMode) {
        switch mode {
        case .walking: self = .start(.walking)
        case .running: self = .start(.running)
        case .both: self = .ask
        }
    }

    /// The activity to start without asking, or `nil` when the user has to
    /// choose first. For the call sites that only need "start now or hold" —
    /// the phone's session screen decides between auto-starting on appear and
    /// showing the picker.
    var immediate: SessionActivity? {
        switch self {
        case .start(let activity): activity
        case .ask: nil
        }
    }
}
