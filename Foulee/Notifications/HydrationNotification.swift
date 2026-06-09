import Foundation

/// Shared identifiers for the hydration reminder notification, its category and
/// its two actions — used both by the scheduler (which builds requests) and the
/// delegate (which handles taps), so they can't drift apart.
enum HydrationNotification {
    static let category = "foulee.hydration.reminder"
    static let drankAction = "foulee.hydration.action.drank"
    static let snoozeAction = "foulee.hydration.action.snooze"

    /// Prefix for the recurring daily reminder requests (one per time slot).
    static let reminderPrefix = "foulee.hydration.reminder."
    /// Prefix for one-off "remind me later" snooze requests.
    static let snoozePrefix = "foulee.hydration.snooze."

    static let title = "Hydratation 💧"
    static let body = "Pense à boire un verre."
    static let snoozeBody = "Petit rappel : pense à boire 💧"
}
