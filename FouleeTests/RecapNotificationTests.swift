import Foundation
import Testing
@testable import Foulee

/// The recap notifications (issue #344).
@Suite("Recap notification")
@MainActor
struct RecapNotificationTests {
    @Test("A recap notification names the recap it opens", arguments: RecapPeriod.Kind.allCases)
    func identifierRoundTrip(kind: RecapPeriod.Kind) {
        #expect(RecapNotification.kind(fromIdentifier: RecapNotification.identifier(for: kind)) == kind)
    }

    @Test("Any other notification opens no recap")
    func otherNotifications() {
        #expect(RecapNotification.kind(fromIdentifier: "foulee.walk.reminder.1") == nil)
        #expect(RecapNotification.kind(fromIdentifier: "foulee.recap.year") == nil)
    }

    @Test("Sunday at 19 h for the week, the 1st at 9 h for the month")
    func triggers() {
        let week = RecapNotification.trigger(for: .week)
        #expect(week.weekday == 1)
        #expect(week.hour == 19)
        #expect(week.day == nil)

        let month = RecapNotification.trigger(for: .month)
        #expect(month.day == 1)
        #expect(month.hour == 9)
        #expect(month.weekday == nil)
    }

    @Test("Both recaps are announced, unless turned off")
    func preference() {
        let defaults = UserDefaults(suiteName: "RecapNotificationTests")!
        defaults.removePersistentDomain(forName: "RecapNotificationTests")
        let preferences = UserPreferences(defaults: defaults)
        #expect(preferences.recapNotificationsEnabled)
        #expect(RecapReminderScheduler.kinds(for: preferences) == [.week, .month])

        preferences.recapNotificationsEnabled = false
        #expect(RecapReminderScheduler.kinds(for: preferences).isEmpty)
        #expect(UserPreferences(defaults: defaults).recapNotificationsEnabled == false)
    }

    /// Taken once, so a rebuild of the home does not open the recap again.
    @Test("A requested recap is handed over once")
    func routerTakesOnce() {
        let router = RecapRouter()
        router.open(.month)
        #expect(router.take() == .month)
        #expect(router.take() == nil)
    }
}
