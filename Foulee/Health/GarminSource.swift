import Foundation

/// Soft Garmin detection (issue #185).
///
/// Pure Foundation, HealthKit-free, so the classification can be tested
/// without a store and can't drift with the framework. Nothing here ever
/// *blocks*: a wrong verdict only changes which hint the Today screen shows —
/// the app stays fully functional either way.
enum GarminSource {
    /// Device families Garmin Connect uses as the *source name* when samples
    /// are attributed to the watch itself ("Forerunner 965") instead of to the
    /// phone app ("Garmin Connect"). Matched on whole, diacritic-folded words
    /// so "Venus" never passes for a "Venu" and "Fēnix" matches "fenix".
    ///
    /// "Lily" is deliberately absent: it's a common first name, and a source
    /// named after its owner ("Lily's iPhone") would be misread as a watch.
    private static let deviceFamilies: Set<String> = [
        "forerunner", "fenix", "epix", "venu", "vivoactive", "vivosmart",
        "vivofit", "vivomove", "instinct", "enduro", "tactix", "quatix",
        "descent", "marq"
    ]

    /// Whether a Health source is a Garmin one. `name` is what the Santé app
    /// shows ("Garmin Connect", "Forerunner 965"), `bundleIdentifier` the
    /// writing app's id ("com.garmin.connect.mobile").
    static func isGarmin(sourceName: String, bundleIdentifier: String) -> Bool {
        let name = folded(sourceName)
        let bundle = folded(bundleIdentifier)
        if bundle.contains("garmin") || name.contains("garmin") { return true }
        // Anything Apple writes — the iPhone, an Apple Watch, the Santé app
        // itself — is never Garmin, and the source name there is whatever the
        // user called their device. Without this, an "Instinct" or a "Marq"
        // chosen as a device name would be classified as a Garmin watch.
        guard !bundle.hasPrefix("com.apple.") else { return false }
        return name
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { deviceFamilies.contains(String($0)) }
    }

    private static func folded(_ value: String) -> String {
        value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

/// What the HealthKit detection found about the watches writing into Santé.
/// The all-false default means "nothing detected", which keeps every adapted
/// hint off — the safe state.
struct GarminStatus: Equatable, Sendable {
    var hasGarminSource = false
    var hasAppleWatchData = false
    /// Newest sample written by a Garmin source *today*, when there is one.
    /// `nil` means Garmin has pushed nothing since midnight.
    var latestGarminSample: Date?
}

/// Freshness rule behind the "Ouvre Garmin Connect pour synchroniser" hint.
///
/// Garmin Connect syncs in bursts — mostly when the user opens it — so a gap
/// is normal, not a bug. The rule is deliberately conservative: the hint only
/// shows in a Garmin-only setup, during the day, once the gap is long enough
/// that opening Garmin Connect really is the useful move.
enum GarminFreshness {
    /// A gap this long during the day means the day's numbers are behind.
    static let staleAfter: TimeInterval = 4 * 60 * 60

    /// Hours during which the hint may appear. Nothing before 11:00 (an empty
    /// morning is normal, and the app's walk window is midday) and nothing in
    /// the evening — nagging at 23:00 wouldn't help anyone.
    static let daytimeHours = 11..<21

    /// Whether the Today screen should show the sync hint.
    ///
    /// - Garmin-only: a user who also has an Apple Watch gets fresh data from
    ///   it, so the hint would be noise (and Apple-Watch-flavoured advice is
    ///   what we're avoiding in the Garmin-only state).
    /// - Never before `daytimeHours`, never after.
    /// - The reference instant is the newest Garmin sample of the day, floored
    ///   at midnight: "nothing since midnight" is exactly the case the hint is
    ///   for, and a sample dated in the future (clock skew) can't trigger it.
    static func needsSyncHint(
        status: GarminStatus,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard status.hasGarminSource, !status.hasAppleWatchData else { return false }
        guard daytimeHours.contains(calendar.component(.hour, from: now)) else { return false }
        let startOfDay = calendar.startOfDay(for: now)
        let reference = max(status.latestGarminSample ?? startOfDay, startOfDay)
        return now.timeIntervalSince(reference) >= staleAfter
    }
}
