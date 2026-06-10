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

    /// UserDefaults stamp written when an action was handled, so the home can
    /// confirm it to the user (toast) — without it, nothing tells them the tap
    /// counted and they log a second glass by hand. `["kind": drank|snooze,
    /// "at": unix time, "amount": mL or minutes]`.
    static let confirmKey = "hydration.action.confirm"
    /// In-process signal posted right after the stamp (covers the case where
    /// the UI is already on screen when the action finishes).
    static let actionHandled = Notification.Name("foulee.hydration.actionHandled")

    /// Stamp a handled action + signal the UI. Shared by the notification
    /// action handler and the in-app "J'ai bu" button so both surface the
    /// same confirmation toast on the home.
    static func confirm(kind: String, amount: Int) {
        UserDefaults.standard.set(
            ["kind": kind, "at": Date().timeIntervalSince1970, "amount": amount],
            forKey: confirmKey
        )
        Task { @MainActor in
            NotificationCenter.default.post(name: actionHandled, object: nil)
        }
    }
}
