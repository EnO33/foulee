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
    /// "at": unix time, "amount": mL or minutes]`, plus the `Undo` of a logged
    /// glass (`"sample"`, `"previousDrinkAt"`).
    static let confirmKey = "hydration.action.confirm"
    /// In-process signal posted right after the stamp (covers the case where
    /// the UI is already on screen when the action finishes).
    static let actionHandled = Notification.Name("foulee.hydration.actionHandled")

    /// What it takes to take a glass back (issue #354): the sample written to
    /// Santé, and the drink the reminder grid was anchored on before it.
    struct Undo: Equatable, Sendable {
        var sample: UUID
        var milliliters: Int
        var previousDrinkAt: TimeInterval?

        /// Read back from a stamp; `nil` when it carries no sample.
        init?(stamp: [String: Any]) {
            guard let raw = stamp["sample"] as? String, let sample = UUID(uuidString: raw) else { return nil }
            self.init(
                sample: sample,
                milliliters: stamp["amount"] as? Int ?? 0,
                previousDrinkAt: stamp["previousDrinkAt"] as? TimeInterval
            )
        }

        init(sample: UUID, milliliters: Int, previousDrinkAt: TimeInterval?) {
            self.sample = sample
            self.milliliters = milliliters
            self.previousDrinkAt = previousDrinkAt
        }
    }

    /// Stamp a handled action + signal the UI. Shared by the notification
    /// action handler and the in-app "J'ai bu" button so both surface the
    /// same confirmation toast on the home — and, for a logged glass, its
    /// « Annuler ».
    static func confirm(kind: String, amount: Int, undo: Undo? = nil) {
        var stamp: [String: Any] = ["kind": kind, "at": Date().timeIntervalSince1970, "amount": amount]
        if let undo {
            stamp["sample"] = undo.sample.uuidString
            stamp["previousDrinkAt"] = undo.previousDrinkAt
        }
        UserDefaults.standard.set(stamp, forKey: confirmKey)
        Task { @MainActor in
            NotificationCenter.default.post(name: actionHandled, object: nil)
        }
    }
}
