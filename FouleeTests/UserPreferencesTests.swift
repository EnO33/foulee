import Foundation
import Testing
@testable import Foulee

@Suite("UserPreferences")
@MainActor
struct UserPreferencesTests {
    @Test("Fresh defaults expose the documented onboarding values")
    func defaults() {
        let prefs = UserPreferences(defaults: cleanDefaults())

        #expect(prefs.activeDays == Weekday.workWeek)
        #expect(prefs.walkWindowStart == .middayWindowStart)
        #expect(prefs.walkWindowEnd == .middayWindowEnd)
        #expect(prefs.minutesGoal == 20)
        #expect(prefs.stepsGoal == 6_000)
        #expect(prefs.hasCompletedOnboarding == false)
    }

    @Test("Edits round-trip through UserDefaults across instances")
    func roundTrip() {
        let defaults = cleanDefaults()
        let first = UserPreferences(defaults: defaults)
        first.activeDays = [.monday, .wednesday, .friday]
        first.walkWindowStart = TimeOfDay(hour: 12, minute: 15)
        first.walkWindowEnd = TimeOfDay(hour: 13, minute: 0)
        first.minutesGoal = 30
        first.stepsGoal = 8_000
        first.hasCompletedOnboarding = true
        first.notificationsEnabled = false
        first.themeMode = .dark

        let second = UserPreferences(defaults: defaults)
        #expect(second.activeDays == [.monday, .wednesday, .friday])
        #expect(second.walkWindowStart == TimeOfDay(hour: 12, minute: 15))
        #expect(second.walkWindowEnd == TimeOfDay(hour: 13, minute: 0))
        #expect(second.minutesGoal == 30)
        #expect(second.stepsGoal == 8_000)
        #expect(second.hasCompletedOnboarding == true)
        #expect(second.notificationsEnabled == false)
        #expect(second.themeMode == .dark)
    }

    @Test("Notifications default to enabled and theme to system")
    func defaultsForNewFields() {
        let prefs = UserPreferences(defaults: cleanDefaults())
        #expect(prefs.notificationsEnabled == true)
        #expect(prefs.themeMode == .system)
    }

    @Test("Weekday bitmask round-trips for every subset")
    func bitmaskRoundTrip() {
        for index in 0..<128 {
            let original = Set<Weekday>(bitmask: index)
            #expect(original.bitmask == index)
        }
    }

    @Test("TimeOfDay rawMinutes is reversible")
    func timeOfDayRoundTrip() {
        for hour in 0..<24 {
            for minute in stride(from: 0, to: 60, by: 5) {
                let original = TimeOfDay(hour: hour, minute: minute)
                let reconstructed = TimeOfDay(rawMinutes: original.rawMinutes)
                #expect(reconstructed == original)
            }
        }
    }

    private func cleanDefaults() -> UserDefaults {
        let suiteName = "foulee-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
