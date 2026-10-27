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
