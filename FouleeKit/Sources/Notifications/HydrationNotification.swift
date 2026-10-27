import Foundation

/// Shared identifiers for the hydration reminder notification, its category and
/// its two actions — used both by the scheduler (which builds requests) and the
/// delegate (which handles taps), so they can't drift apart.
nonisolated public enum HydrationNotification {
    public static let category = "foulee.hydration.reminder"
    public static let drankAction = "foulee.hydration.action.drank"
    public static let snoozeAction = "foulee.hydration.action.snooze"

    /// Prefix for the recurring daily reminder requests (one per time slot).
    public static let reminderPrefix = "foulee.hydration.reminder."
    /// Prefix for one-off "remind me later" snooze requests.
    public static let snoozePrefix = "foulee.hydration.snooze."

    // Read when the reminder is scheduled, in the language of the app
    // scheduling it: a phone or watch switched to another language speaks it
    // from the next reschedule on.
    public static var title: String { kitText("Hydratation 💧") }
    public static var body: String { kitText("Pense à boire un verre.") }
    public static var snoozeBody: String { kitText("Petit rappel : pense à boire 💧") }

    /// UserDefaults stamp written when an action was handled, so the home can
    /// confirm it to the user (toast) — without it, nothing tells them the tap
    /// counted and they log a second glass by hand. `["kind": drank|snooze,
    /// "at": unix time, "amount": mL or minutes]`, plus the `Undo` of a logged
    /// glass (`"sample"`, `"previousDrinkAt"`).
    public static let confirmKey = "hydration.action.confirm"
    /// In-process signal posted right after the stamp (covers the case where
    /// the UI is already on screen when the action finishes).
    public static let actionHandled = Notification.Name("foulee.hydration.actionHandled")

    /// What it takes to take a glass back (issue #354): the sample written to
    /// Santé, and the drink the reminder grid was anchored on before it.
    nonisolated public struct Undo: Equatable, Sendable {
        public var sample: UUID
        public var milliliters: Int
        public var previousDrinkAt: TimeInterval?

        /// Read back from a stamp; `nil` when it carries no sample.
        public init?(stamp: [String: Any]) {
            guard let raw = stamp["sample"] as? String, let sample = UUID(uuidString: raw) else { return nil }
            self.init(
                sample: sample,
                milliliters: stamp["amount"] as? Int ?? 0,
                previousDrinkAt: stamp["previousDrinkAt"] as? TimeInterval
            )
        }

        public init(sample: UUID, milliliters: Int, previousDrinkAt: TimeInterval?) {
            self.sample = sample
            self.milliliters = milliliters
            self.previousDrinkAt = previousDrinkAt
        }
    }

    /// Stamp a handled action + signal the UI. Shared by the notification
    /// action handler and the in-app "J'ai bu" button so both surface the
    /// same confirmation toast on the home — and, for a logged glass, its
    /// « Annuler ».
    public static func confirm(kind: String, amount: Int, undo: Undo? = nil) {
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
