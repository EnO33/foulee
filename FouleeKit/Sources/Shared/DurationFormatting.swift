import Foundation

/// A duration in minutes as the app says it (issue #366): `45 min` under an
/// hour, then hours — `1 h`, `1 h 05`, `6 h`. One rule for every total, so a
/// week of activity reads « 6 h » and never « 360 min ».
///
/// French is written that way by hand; any other language gets the system's
/// abbreviated units — « 1 hr, 5 min » (issue #586).
nonisolated public func durationText(minutes: Int, locale: Locale = .app) -> String {
    let minutes = max(minutes, 0)
    guard locale.language.languageCode == .french else {
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale))
    }
    guard minutes >= 60 else { return "\(minutes) min" }
    let rest = minutes % 60
    return rest == 0 ? "\(minutes / 60) h" : String(format: "%d h %02d", minutes / 60, rest)
}

/// A duration as VoiceOver says it (issue #596): « 1 heure et 5 minutes »,
/// « 12 minutes et 34 secondes ». The written forms are read wrong — « 12:34 »
/// as a time of day, « 1 h 05 » digit by digit.
///
/// Seconds only show when there are some, so a whole number of minutes reads
/// « 45 minutes » and nothing more.
nonisolated public func spokenDurationText(seconds: TimeInterval, locale: Locale = .app) -> String {
    Duration.seconds(max(Int(seconds), 0))
        .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(locale))
}

/// `spokenDurationText(seconds:)` for a count of minutes, as `durationText`
/// takes them.
nonisolated public func spokenDurationText(minutes: Int, locale: Locale = .app) -> String {
    spokenDurationText(seconds: TimeInterval(minutes * 60), locale: locale)
}
