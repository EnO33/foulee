import Foundation
import WidgetKit

/// Single value the timeline provider hands to the complication views —
/// just a date + the current streak.
struct StreakEntry: TimelineEntry, Sendable {
    let date: Date
    let streak: Int

    static let placeholder = StreakEntry(date: .now, streak: 0)
}
