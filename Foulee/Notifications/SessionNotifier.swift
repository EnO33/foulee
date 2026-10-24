import Dependencies
import FouleeKit
import Foundation

/// Sends the notification of an outing that just landed (issue #529): a
/// watch's, Garmin's, another app's — any outing this iPhone did not record
/// itself.
///
/// Runs on every Health wake for a workout and on every outing the Garmin
/// watch sends, from the background as often as not. The register
/// (`SessionAnnouncements`) decides; this reads Santé, keeps the register in
/// the defaults and hands the notices to iOS.
nonisolated struct SessionNotifier {
    /// `UserPreferences`' key, read straight from the defaults like the
    /// hydration observer's: a background wake has no preferences object.
    static let enabledKey = "preferences.sessionNotificationsEnabled"
    private static let registerKey = "sessionNotifications.register"
    /// Six calendar months back, for the comparisons, and a few days to spare.
    static let daysBack = 190

    @Dependency(\.healthKit) private var healthKit
    @Dependency(\.notifications) private var notifications

    /// Announce what landed since the last call. Turned off, the register
    /// still follows, so turning it back on announces nothing from before.
    func outingsChanged(now: Date = .now, defaults: UserDefaults = .standard) async {
        // A refused read (locked phone) keeps the register as it was: the
        // next wake reads the same outings.
        guard let workouts = try? await healthKit.recentWorkouts(Self.daysBack) else { return }
        let notices = Self.update(defaults, now: now) { $0.notices(for: workouts, now: now) }
        guard Self.isEnabled(defaults) else { return }
        for notice in notices {
            // Denied or failed: nothing to tell anyone, the outing is in the
            // app regardless.
            try? await notifications.scheduleSessionNotice(notice)
        }
    }

    /// An outing recorded on this iPhone: its end screen says it all.
    static func recordedHere(from start: Date, to end: Date, defaults: UserDefaults = .standard) {
        update(defaults, now: start) { $0.markAnnounced(from: start, to: end) }
    }

    /// Opens the register at the first launch with this feature, so the
    /// outings recorded before it are never announced.
    static func prepare(now: Date = .now, defaults: UserDefaults = .standard) {
        update(defaults, now: now) { _ in }
    }

    static func isEnabled(_ defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: enabledKey) as? Bool) ?? true
    }

    /// Several workouts of one Garmin sync wake the observer at once: the
    /// read-modify-write of the register goes one at a time, or two wakes
    /// would each announce the same outing under its own identifier.
    private static let lock = NSLock()

    @discardableResult
    private static func update<Result>(
        _ defaults: UserDefaults,
        now: Date,
        _ change: (inout SessionAnnouncements) -> Result
    ) -> Result {
        lock.withLock {
            var register = defaults.data(forKey: registerKey)
                .flatMap { try? JSONDecoder().decode(SessionAnnouncements.self, from: $0) }
                ?? SessionAnnouncements(since: now)
            let result = change(&register)
            if let data = try? JSONEncoder().encode(register) {
                defaults.set(data, forKey: registerKey)
            }
            return result
        }
    }
}

/// What `ActiveWalkStore` tells the notifier, injectable so its tests leave
/// the defaults alone.
nonisolated struct SessionNotificationsClient: Sendable {
    var recordedHere: @Sendable (_ start: Date, _ end: Date) -> Void
}

nonisolated extension SessionNotificationsClient: DependencyKey {
    static let liveValue = SessionNotificationsClient { SessionNotifier.recordedHere(from: $0, to: $1) }
    static let previewValue = SessionNotificationsClient { _, _ in }
    static let testValue = previewValue
}

nonisolated extension DependencyValues {
    var sessionNotifications: SessionNotificationsClient {
        get { self[SessionNotificationsClient.self] }
        set { self[SessionNotificationsClient.self] = newValue }
    }
}
