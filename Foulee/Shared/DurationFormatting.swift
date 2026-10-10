import Foundation

/// A duration in minutes as the app says it (issue #366): `45 min` under an
/// hour, then hours — `1 h`, `1 h 05`, `6 h`. One rule for every total, so a
/// week of activity reads « 6 h » and never « 360 min ».
func durationText(minutes: Int) -> String {
    guard minutes >= 60 else { return "\(max(minutes, 0)) min" }
    let rest = minutes % 60
    return rest == 0 ? "\(minutes / 60) h" : String(format: "%d h %02d", minutes / 60, rest)
}
