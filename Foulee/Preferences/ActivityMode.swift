import Foundation

/// Which activity the user wants Foulée to support. Walking is the app's
/// original — and until now only — scope, so it stays the default: an
/// install that has never written the preference must keep behaving exactly
/// as it did before (issue #219).
///
/// A read-side preference for what the app *proposes*, never for what it has
/// already *credited*: the streak, the record and the calendar are computed
/// from `appleExerciseTime` and workout minutes across every activity type,
/// and nothing here reaches them. Switching modes therefore moves no history —
/// that is the running work's contract, pinned by `ActivityModeNeutralityTests`.
enum ActivityMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case walking
    case running
    case both

    var id: String { rawValue }

    /// Segment titles for the Settings picker (issue #220). Short on purpose —
    /// three of them share one segmented control's width.
    var label: String {
        switch self {
        case .walking: "Marche"
        case .running: "Course"
        case .both: "Les deux"
        }
    }
}
