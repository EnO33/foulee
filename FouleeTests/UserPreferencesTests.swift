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
        // Issue #219: an install that never wrote the key must read walking,
        // so shipping the running work moves nobody off their current app.
        #expect(prefs.activityMode == .walking)
    }

    /// Issue #329: on for a new install, reminders still off.
    @Test("A new install starts with hydration on and its reminders off")
    func newInstallHydration() {
        let defaults = cleanDefaults()
        let prefs = UserPreferences(defaults: defaults)
        #expect(prefs.hydrationEnabled)
        #expect(prefs.hydrationRemindersEnabled == false)

        // Still on after onboarding completes and the app relaunches: the
        // default was written, not merely assumed.
        prefs.hasCompletedOnboarding = true
        #expect(UserPreferences(defaults: defaults).hydrationEnabled)
    }

    /// An install that finished onboarding before this change keeps what it
    /// had, even though it never wrote the key.
    @Test("An existing install that never touched hydration keeps it off")
    func existingInstallUnchanged() {
        let defaults = cleanDefaults()
        defaults.set(true, forKey: "preferences.hasCompletedOnboarding")
        #expect(UserPreferences(defaults: defaults).hydrationEnabled == false)
    }

    @Test("A choice already made is kept, whatever it was", arguments: [true, false])
    func explicitChoiceKept(choice: Bool) {
        let defaults = cleanDefaults()
        defaults.set(choice, forKey: "preferences.hydrationEnabled")
        #expect(UserPreferences(defaults: defaults).hydrationEnabled == choice)
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
        first.activityMode = .both

        let second = UserPreferences(defaults: defaults)
        #expect(second.activeDays == [.monday, .wednesday, .friday])
        #expect(second.walkWindowStart == TimeOfDay(hour: 12, minute: 15))
        #expect(second.walkWindowEnd == TimeOfDay(hour: 13, minute: 0))
        #expect(second.minutesGoal == 30)
        #expect(second.stepsGoal == 8_000)
        #expect(second.hasCompletedOnboarding == true)
        #expect(second.notificationsEnabled == false)
        #expect(second.themeMode == .dark)
        #expect(second.activityMode == .both)
    }

    /// #220 puts a picker on this preference, so all three of its cases now
    /// reach `UserDefaults` — the round-trip above only ever exercised `.both`.
    @Test("Every activity mode survives a relaunch")
    func activityModeRoundTripsForEveryCase() {
        for mode in ActivityMode.allCases {
            let defaults = cleanDefaults()
            UserPreferences(defaults: defaults).activityMode = mode
            #expect(UserPreferences(defaults: defaults).activityMode == mode)
        }
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
