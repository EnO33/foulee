import Foundation

/// What one CoreMotion estimate says about the two activities Foulée records,
/// and how sure the device is — the half of motion classification that **both
/// platforms must agree on**.
///
/// Compiled into the phone and the watch alike (see Project.swift), because the
/// alternative is a bug nobody could explain: the watch naming a stretch
/// « Course » on the wrist while the phone, reading the same CoreMotion history
/// afterwards, files the session as a walk. The two would be right by their own
/// rules and contradict each other on one screen.
///
/// Only the *rule* is shared. What surrounds it is genuinely different work —
/// the watch decides live whether to switch (issue #249), the phone reduces a
/// finished session's history into segments (issue #246) — and neither belongs
/// here.

/// How sure CoreMotion says it is. Mirrors `CMMotionActivityConfidence`; the
/// raw values are pinned against the real enum in the test suites.
///
/// `unrecognised` exists because a future OS could add a level, and folding an
/// unknown value into `low` would claim the device said something it did not.
/// It sorts *below* `low`, so any threshold rejects it.
enum MotionActivityConfidence: Int, CaseIterable, Comparable, Sendable {
    case unrecognised = -1
    case low = 0
    case medium = 1
    case high = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What one estimate amounts to.
///
/// `noEvidence` is a first-class answer, not an error: CoreMotion asserting
/// nothing is a frequent, normal reading — `CMMotionActivity`'s flags can all
/// be false — and so is asserting something Foulée does not record (cycling, a
/// car). Both mean the same thing here, and what to *do* about it differs by
/// platform: the watch keeps the current activity, the phone falls back to
/// walking. Neither decision is taken in this file.
enum MotionActivityReading: Equatable, Sendable {
    case activity(SessionActivity)
    case noEvidence

    /// Reduce the flags to at most one activity.
    ///
    /// Only `walking` and `running` are consulted, and **exactly one** of them
    /// must be set. `if walking … else if running` would be wrong by
    /// construction: the flags are not mutually exclusive, so that form
    /// silently prefers walking whenever the device asserts both — precisely
    /// the moment it is least sure.
    ///
    /// Everything else yields `noEvidence` without needing a case of its own:
    /// both flags clear is what a stationary wearer, a bike ride, a car journey
    /// and an unclassifiable estimate all look like from here.
    static func of(
        walking: Bool,
        running: Bool,
        confidence: MotionActivityConfidence,
        minimumConfidence: MotionActivityConfidence
    ) -> MotionActivityReading {
        guard confidence >= minimumConfidence else { return .noEvidence }
        switch (walking, running) {
        case (true, false): return .activity(.walking)
        case (false, true): return .activity(.running)
        default: return .noEvidence
        }
    }
}
