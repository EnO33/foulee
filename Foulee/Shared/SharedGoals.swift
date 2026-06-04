import Foundation

/// The user's daily goals, shared with the widgets through the app group so a
/// Lock Screen / Home Screen widget can measure progress against the *real*
/// goals instead of a hard-coded default. The app writes them whenever they
/// change; widgets read them. When the app group isn't reachable (e.g. the
/// watch, which doesn't share this container), the defaults are returned.
enum SharedGoals {
    static let suiteName = "group.com.eno33.foulee"

    static let defaultSteps = 6_000
    static let defaultMinutes = 20

    private static var store: UserDefaults? { UserDefaults(suiteName: suiteName) }

    private enum Keys {
        static let steps = "shared.stepsGoal"
        static let minutes = "shared.minutesGoal"
    }

    /// Persist the current goals into the shared container (called by the app).
    static func write(stepsGoal: Int, minutesGoal: Int) {
        guard let store else { return }
        store.set(stepsGoal, forKey: Keys.steps)
        store.set(minutesGoal, forKey: Keys.minutes)
    }

    static var stepsGoal: Int { (store?.object(forKey: Keys.steps) as? Int) ?? defaultSteps }

    static var minutesGoal: Int { (store?.object(forKey: Keys.minutes) as? Int) ?? defaultMinutes }
}
