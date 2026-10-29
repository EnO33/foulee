import Dependencies
import FouleeKit
import Foundation
import Observation

/// Single source of truth for user-tunable settings. Reads/writes
/// `UserDefaults` synchronously on every mutation so SwiftUI stays
/// in sync without an explicit save call.
///
/// Initialiser takes an injectable `UserDefaults` so previews and tests
/// can use a clean suite without polluting the real defaults database.
///
/// With a `cloud` store, every setting but the onboarding flag follows the
/// user's other iPhones through iCloud (issue #616, `CloudSettingsSync`).
@Observable
final class UserPreferences {
    var activeDays: Set<Weekday> {
        didSet { save(activeDays.bitmask, forKey: Keys.activeDays) }
    }
    var walkWindowStart: TimeOfDay {
        didSet { save(walkWindowStart.rawMinutes, forKey: Keys.walkWindowStart) }
    }
    var walkWindowEnd: TimeOfDay {
        didSet { save(walkWindowEnd.rawMinutes, forKey: Keys.walkWindowEnd) }
    }
    var minutesGoal: Int {
        didSet { save(minutesGoal, forKey: Keys.minutesGoal) }
    }
    var stepsGoal: Int {
        didSet { save(stepsGoal, forKey: Keys.stepsGoal) }
    }
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }
    var notificationsEnabled: Bool {
        didSet { save(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }
    var themeMode: ThemeMode {
        didSet { save(themeMode.rawValue, forKey: Keys.themeMode) }
    }
    /// Hydration tracking. Intake is stored in Apple Health (`dietaryWater`);
    /// these only hold the goal and glass size.
    ///
    /// **On for a new install, untouched for an existing one** (issue #329).
    /// See `init` for how the two are told apart. Reminders stay opt-in.
    var hydrationEnabled: Bool {
        didSet { save(hydrationEnabled, forKey: Keys.hydrationEnabled) }
    }
    var hydrationGoalML: Int {
        didSet { save(hydrationGoalML, forKey: Keys.hydrationGoalML) }
    }
    var hydrationGlassML: Int {
        didSet { save(hydrationGlassML, forKey: Keys.hydrationGlassML) }
    }
    var hydrationRemindersEnabled: Bool {
        didSet { save(hydrationRemindersEnabled, forKey: Keys.hydrationRemindersEnabled) }
    }
    var hydrationWindowStart: TimeOfDay {
        didSet { save(hydrationWindowStart.rawMinutes, forKey: Keys.hydrationWindowStart) }
    }
    var hydrationWindowEnd: TimeOfDay {
        didSet { save(hydrationWindowEnd.rawMinutes, forKey: Keys.hydrationWindowEnd) }
    }
    var hydrationIntervalMinutes: Int {
        didSet { save(hydrationIntervalMinutes, forKey: Keys.hydrationIntervalMinutes) }
    }
    var hydrationSnoozeMinutes: Int {
        didSet { save(hydrationSnoozeMinutes, forKey: Keys.hydrationSnoozeMinutes) }
    }
    /// Which activity the app supports. Defaults to walking so existing
    /// installs — which never wrote this key — stay exactly where they are.
    var activityMode: ActivityMode {
        didSet { save(activityMode.rawValue, forKey: Keys.activityMode) }
    }
    /// The Monday and 1st-of-the-month recap notifications (issue #344). On
    /// unless turned off: the recap is the point of having one.
    var recapNotificationsEnabled: Bool {
        didSet { save(recapNotificationsEnabled, forKey: Keys.recapNotificationsEnabled) }
    }
    /// The notification of an outing that landed from a watch or another
    /// app (issue #529). On unless turned off.
    var sessionNotificationsEnabled: Bool {
        didSet { save(sessionNotificationsEnabled, forKey: Keys.sessionNotificationsEnabled) }
    }

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let cloud: SettingsKeyValueStore?
    /// Set while a set pulled from iCloud is applied, so that applying it is
    /// not taken for a change made here and sent back with a newer stamp.
    @ObservationIgnored
    private var isApplyingCloud = false
    @ObservationIgnored
    @Dependency(\.date) private var date
    @ObservationIgnored
    @Dependency(\.outingMerges) private var outingMerges

    init(defaults: UserDefaults = .standard, cloud: SettingsKeyValueStore? = nil) {
        self.defaults = defaults
        self.cloud = cloud
        let rawDays = defaults.object(forKey: Keys.activeDays) as? Int
        self.activeDays = rawDays.map(Set<Weekday>.init(bitmask:)) ?? Weekday.workWeek
        let rawStart = defaults.object(forKey: Keys.walkWindowStart) as? Int
        let walkWindowStart = rawStart.map(TimeOfDay.init(rawMinutes:)) ?? .middayWindowStart
        self.walkWindowStart = walkWindowStart
        let rawEnd = defaults.object(forKey: Keys.walkWindowEnd) as? Int
        self.walkWindowEnd = Self.validWindowEnd(
            rawEnd.map(TimeOfDay.init(rawMinutes:)) ?? .middayWindowEnd,
            after: walkWindowStart,
            key: Keys.walkWindowEnd,
            in: defaults
        )
        self.minutesGoal = (defaults.object(forKey: Keys.minutesGoal) as? Int) ?? 20
        self.stepsGoal = (defaults.object(forKey: Keys.stepsGoal) as? Int) ?? 6_000
        let hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.notificationsEnabled = (defaults.object(forKey: Keys.notificationsEnabled) as? Bool) ?? true
        let rawTheme = defaults.string(forKey: Keys.themeMode)
        self.themeMode = rawTheme.flatMap(ThemeMode.init(rawValue:)) ?? .system
        // A new install starts with hydration on (issue #329); one that has
        // already been through onboarding keeps what it had — off — whether or
        // not its owner ever touched the toggle. « Never written » alone cannot
        // tell the two apart, the onboarding flag can.
        //
        // Written straight away, not just read: once onboarding completes, the
        // same rule would otherwise read the missing key as « existing
        // install » on the next launch, and switch it back off.
        if defaults.object(forKey: Keys.hydrationEnabled) == nil, !hasCompletedOnboarding {
            defaults.set(true, forKey: Keys.hydrationEnabled)
        }
        self.hydrationEnabled = defaults.bool(forKey: Keys.hydrationEnabled)
        self.hydrationGoalML = (defaults.object(forKey: Keys.hydrationGoalML) as? Int) ?? 2_000
        self.hydrationGlassML = (defaults.object(forKey: Keys.hydrationGlassML) as? Int) ?? 250
        self.hydrationRemindersEnabled = defaults.bool(forKey: Keys.hydrationRemindersEnabled)
        let rawHydrationStart = defaults.object(forKey: Keys.hydrationWindowStart) as? Int
        let hydrationWindowStart = rawHydrationStart.map(TimeOfDay.init(rawMinutes:)) ?? TimeOfDay(rawMinutes: 9 * 60)
        self.hydrationWindowStart = hydrationWindowStart
        let rawHydrationEnd = defaults.object(forKey: Keys.hydrationWindowEnd) as? Int
        self.hydrationWindowEnd = Self.validWindowEnd(
            rawHydrationEnd.map(TimeOfDay.init(rawMinutes:)) ?? TimeOfDay(rawMinutes: 21 * 60),
            after: hydrationWindowStart,
            key: Keys.hydrationWindowEnd,
            in: defaults
        )
        self.hydrationIntervalMinutes = (defaults.object(forKey: Keys.hydrationIntervalMinutes) as? Int) ?? 120
        self.hydrationSnoozeMinutes = (defaults.object(forKey: Keys.hydrationSnoozeMinutes) as? Int) ?? 15
        let rawActivity = defaults.string(forKey: Keys.activityMode)
        self.activityMode = rawActivity.flatMap(ActivityMode.init(rawValue:)) ?? .walking
        self.recapNotificationsEnabled = (defaults.object(forKey: Keys.recapNotificationsEnabled) as? Bool) ?? true
        self.sessionNotificationsEnabled = SessionNotifier.isEnabled(defaults)
    }
}

extension UserPreferences {
    /// Brings in what another iPhone changed: at launch and each time iCloud
    /// reports a change. Sends this one's settings instead when they are the
    /// newer.
    func syncWithCloud() {
        guard let cloud else { return }
        let outcome = CloudSettingsSync.reconcile(
            Keys.synced,
            local: defaults,
            cloud: cloud,
            seeds: hasCompletedOnboarding
        )
        if outcome == .pulled { reload() }
    }

    /// Réglages › Réinitialiser (issue #618): every setting back to its
    /// default and every outing merge undone, on this iPhone and, through
    /// iCloud, on the others; then the onboarding again, on this iPhone only.
    /// Nothing in Santé is touched.
    func reset() {
        if let cloud {
            CloudSettingsSync.reset(Keys.synced, local: defaults, cloud: cloud, now: date.now)
        } else {
            for key in Keys.synced { defaults.removeObject(forKey: key) }
        }
        outingMerges.write([])
        // Before the reload: a new install's defaults, hydration on included.
        defaults.removeObject(forKey: Keys.hasCompletedOnboarding)
        reload()
        hasCompletedOnboarding = false
    }

    private func save(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        guard let cloud, !isApplyingCloud else { return }
        CloudSettingsSync.localDidChange(Keys.synced, local: defaults, cloud: cloud, now: date.now)
    }

    /// Reads the synced settings back from the defaults, through `init` so
    /// that the fallbacks and repairs are the same as at launch.
    private func reload() {
        isApplyingCloud = true
        defer { isApplyingCloud = false }
        let fresh = UserPreferences(defaults: defaults)
        activeDays = fresh.activeDays
        walkWindowStart = fresh.walkWindowStart
        walkWindowEnd = fresh.walkWindowEnd
        minutesGoal = fresh.minutesGoal
        stepsGoal = fresh.stepsGoal
        notificationsEnabled = fresh.notificationsEnabled
        themeMode = fresh.themeMode
        hydrationEnabled = fresh.hydrationEnabled
        hydrationGoalML = fresh.hydrationGoalML
        hydrationGlassML = fresh.hydrationGlassML
        hydrationRemindersEnabled = fresh.hydrationRemindersEnabled
        hydrationWindowStart = fresh.hydrationWindowStart
        hydrationWindowEnd = fresh.hydrationWindowEnd
        hydrationIntervalMinutes = fresh.hydrationIntervalMinutes
        hydrationSnoozeMinutes = fresh.hydrationSnoozeMinutes
        activityMode = fresh.activityMode
        recapNotificationsEnabled = fresh.recapNotificationsEnabled
        sessionNotificationsEnabled = fresh.sessionNotificationsEnabled
    }

    /// A stored window end, corrected when it falls before its start (#395) —
    /// a value written before the pickers were bounded. The fix is written
    /// back, so the reminder schedulers, which read the defaults directly,
    /// see the same window as the screens.
    private static func validWindowEnd(
        _ end: TimeOfDay,
        after start: TimeOfDay,
        key: String,
        in defaults: UserDefaults
    ) -> TimeOfDay {
        let valid = TimeOfDay.validEnd(end, after: start)
        if valid != end { defaults.set(valid.rawMinutes, forKey: key) }
        return valid
    }
}

private enum Keys {
    static let activeDays = "preferences.activeDays"
    static let walkWindowStart = "preferences.walkWindowStart"
    static let walkWindowEnd = "preferences.walkWindowEnd"
    static let minutesGoal = "preferences.minutesGoal"
    static let stepsGoal = "preferences.stepsGoal"
    static let hasCompletedOnboarding = "preferences.hasCompletedOnboarding"
    static let notificationsEnabled = "preferences.notificationsEnabled"
    static let themeMode = "preferences.themeMode"
    static let hydrationEnabled = "preferences.hydrationEnabled"
    static let hydrationGoalML = "preferences.hydrationGoalML"
    static let hydrationGlassML = "preferences.hydrationGlassML"
    static let hydrationRemindersEnabled = "preferences.hydrationRemindersEnabled"
    static let hydrationWindowStart = "preferences.hydrationWindowStart"
    static let hydrationWindowEnd = "preferences.hydrationWindowEnd"
    static let hydrationIntervalMinutes = "preferences.hydrationIntervalMinutes"
    static let hydrationSnoozeMinutes = "preferences.hydrationSnoozeMinutes"
    static let activityMode = "preferences.activityMode"
    static let recapNotificationsEnabled = "preferences.recapNotificationsEnabled"
    static let sessionNotificationsEnabled = SessionNotifier.enabledKey

    /// Everything iCloud carries: all but the onboarding flag, which says
    /// what this iPhone has been through, not what its owner chose.
    static let synced = [
        activeDays, walkWindowStart, walkWindowEnd, minutesGoal, stepsGoal,
        notificationsEnabled, themeMode, hydrationEnabled, hydrationGoalML,
        hydrationGlassML, hydrationRemindersEnabled, hydrationWindowStart,
        hydrationWindowEnd, hydrationIntervalMinutes, hydrationSnoozeMinutes,
        activityMode, recapNotificationsEnabled, sessionNotificationsEnabled,
    ]
}
