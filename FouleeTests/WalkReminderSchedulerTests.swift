import Dependencies
import Foundation
import Testing
@testable import Foulee

@Suite("WalkReminderScheduler")
struct WalkReminderSchedulerTests {
    @Test("Reminder time is exactly 10 minutes before window start")
    func reminderTimeLead() {
        let time = WalkReminderScheduler.reminderTime(
            forWindowStart: TimeOfDay(hour: 12, minute: 0)
        )
        #expect(time == TimeOfDay(hour: 11, minute: 50))
    }

    @Test("Reminder time clamps to 00:00 if window start is earlier than the lead")
    func reminderTimeClamp() {
        let time = WalkReminderScheduler.reminderTime(
            forWindowStart: TimeOfDay(hour: 0, minute: 5)
        )
        #expect(time == TimeOfDay(hour: 0, minute: 0))
    }

    @Test("Produces exactly one reminder per active day, sorted Mon → Sun")
    @MainActor
    func remindersPerActiveDay() {
        let prefs = UserPreferences(defaults: cleanDefaults())
        prefs.activeDays = [.tuesday, .friday, .monday]
        prefs.walkWindowStart = TimeOfDay(hour: 12, minute: 30)

        let reminders = WalkReminderScheduler.reminders(for: prefs)

        #expect(reminders.map(\.weekday) == [.monday, .tuesday, .friday])
        #expect(reminders.allSatisfy { $0.time == TimeOfDay(hour: 12, minute: 20) })
        #expect(reminders.map(\.identifier).count == Set(reminders.map(\.identifier)).count)
    }

    @Test("Sync sends the computed schedule to the notifications client")
    @MainActor
    func syncCallsClient() async {
        let captured = LockedRef<[WalkReminder]>([])
        await withDependencies {
            $0.notifications = NotificationsClient(
                requestAuthorization: { true },
                replaceWalkReminders: { captured.set($0) },
                pendingReminderIdentifiers: { [] }
            )
        } operation: {
            let prefs = UserPreferences(defaults: cleanDefaults())
            prefs.activeDays = [.monday, .wednesday]
            prefs.walkWindowStart = TimeOfDay(hour: 12, minute: 0)

            let scheduler = WalkReminderScheduler()
            await scheduler.sync(with: prefs)

            #expect(captured.value.map(\.weekday) == [.monday, .wednesday])
            #expect(captured.value.allSatisfy { $0.time == TimeOfDay(hour: 11, minute: 50) })
        }
    }

    @Test("A throwing client is swallowed at the scheduler boundary")
    @MainActor
    func syncSwallowsErrors() async {
        struct Boom: Error {}
        await withDependencies {
            $0.notifications = NotificationsClient(
                requestAuthorization: { true },
                replaceWalkReminders: { _ in throw Boom() },
                pendingReminderIdentifiers: { [] }
            )
        } operation: {
            let prefs = UserPreferences(defaults: cleanDefaults())
            await WalkReminderScheduler().sync(with: prefs)
            // No assertion needed: the test passes by not propagating.
        }
    }

    private func cleanDefaults() -> UserDefaults {
        let suiteName = "foulee-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
