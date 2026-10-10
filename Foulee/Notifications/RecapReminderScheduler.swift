import Dependencies
import Foundation

/// Keeps the recap notifications in step with the preference (issue #344).
struct RecapReminderScheduler {
    @Dependency(\.notifications) private var notifications

    /// The recaps to announce: both, or none.
    @MainActor
    static func kinds(for preferences: UserPreferences) -> [RecapPeriod.Kind] {
        preferences.recapNotificationsEnabled ? RecapPeriod.Kind.allCases : []
    }

    /// Safe to call repeatedly — the client replaces the previous requests.
    /// Failures are absorbed, like the walk reminders': the toggle in Réglages
    /// is the user's recourse.
    @MainActor
    func sync(with preferences: UserPreferences) async {
        let kinds = Self.kinds(for: preferences)
        if !kinds.isEmpty {
            _ = try? await notifications.requestAuthorization()
        }
        try? await notifications.replaceRecapReminders(kinds)
    }
}
