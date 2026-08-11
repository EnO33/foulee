import os

/// The two boundaries where a failure would otherwise be invisible.
///
/// Foulée had no logging at all before issue #273 — `import os` appeared in
/// half a dozen files, always for `OSAllocatedUnfairLock`, never for a log
/// line. That is not an oversight to fix everywhere at once: a log is worth
/// writing where the failure is *silent* and where the next person to look is
/// standing outdoors with a watch on their wrist. Everywhere else, an error
/// already reaches a screen.
///
/// Both categories below name a path that has cost something:
///
/// - The session path is the one that shipped **two broken versions and lost
///   two outings** (issue #256). The cause was on screen the whole time, in
///   `lastError`, rendered only where `reset()` had already cleared it. What
///   unblocked it was showing the message, not analysing harder.
/// - The Live Activity path is about to decide half of épic #272. Issue #275
///   asks whether `Activity.request` can start one from a mirrored-workout
///   background wake — Apple's own documentation and its own WWDC session
///   disagree. `try?` makes "ActivityKit refused" and "the handler never ran"
///   look identical, so the probe cannot conclude anything until this exists.
///
/// Subsystem matches the bundle identifier so `log stream --subsystem
/// com.eno33.foulee` picks up phone and watch together.
enum FouleeLog {
    private static let subsystem = "com.eno33.foulee"

    /// Starting, splitting, saving and losing a workout session. Watch side
    /// mostly, since that is where the session lives.
    static let session = Logger(subsystem: subsystem, category: "session")

    /// Live Activity lifecycle. It fails for reasons the user causes (Live
    /// Activities switched off in Réglages) and reasons only the system knows;
    /// the two want telling apart.
    static let liveActivity = Logger(subsystem: subsystem, category: "live-activity")
}
