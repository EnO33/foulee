import Foundation
import Observation

/// Single source of truth for user-tunable settings. Reads/writes
/// `UserDefaults` synchronously on every mutation so SwiftUI stays
/// in sync without an explicit save call.
///
/// Initialiser takes an injectable `UserDefaults` so previews and tests
/// can use a clean suite without polluting the real defaults database.
@MainActor
@Observable
final class UserPreferences {
    var activeDays: Set<Weekday> {
        didSet { defaults.set(activeDays.bitmask, forKey: Keys.activeDays) }
    }
    var walkWindowStart: TimeOfDay {
        didSet { defaults.set(walkWindowStart.rawMinutes, forKey: Keys.walkWindowStart) }
    }
    var walkWindowEnd: TimeOfDay {
        didSet { defaults.set(walkWindowEnd.rawMinutes, forKey: Keys.walkWindowEnd) }
    }
    var minutesGoal: Int {
        didSet { defaults.set(minutesGoal, forKey: Keys.minutesGoal) }
    }
    var stepsGoal: Int {
        didSet { defaults.set(stepsGoal, forKey: Keys.stepsGoal) }
    }
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawDays = defaults.object(forKey: Keys.activeDays) as? Int
        self.activeDays = rawDays.map(Set<Weekday>.init(bitmask:)) ?? Weekday.workWeek
        let rawStart = defaults.object(forKey: Keys.walkWindowStart) as? Int
        self.walkWindowStart = rawStart.map(TimeOfDay.init(rawMinutes:)) ?? .middayWindowStart
        let rawEnd = defaults.object(forKey: Keys.walkWindowEnd) as? Int
        self.walkWindowEnd = rawEnd.map(TimeOfDay.init(rawMinutes:)) ?? .middayWindowEnd
        self.minutesGoal = (defaults.object(forKey: Keys.minutesGoal) as? Int) ?? 20
        self.stepsGoal = (defaults.object(forKey: Keys.stepsGoal) as? Int) ?? 6_000
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }
}

private enum Keys {
    static let activeDays = "preferences.activeDays"
    static let walkWindowStart = "preferences.walkWindowStart"
    static let walkWindowEnd = "preferences.walkWindowEnd"
    static let minutesGoal = "preferences.minutesGoal"
    static let stepsGoal = "preferences.stepsGoal"
    static let hasCompletedOnboarding = "preferences.hasCompletedOnboarding"
}
