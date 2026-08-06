import Foundation
import WidgetKit

/// Single value the timeline provider hands to the complication views —
/// a date, the current streak, and which activity to draw.
///
/// Shared with the iPhone Série widget, which lists this file in its own
/// sources (see Project.swift).
struct StreakEntry: TimelineEntry, Sendable {
    let date: Date
    let streak: Int
    /// Which figure the surface should show (issue #222). Defaulted rather
    /// than required because the watch complication draws a flame and no
    /// activity figure at all: only the iPhone widget passes it, from the
    /// app-group snapshot.
    var activityMode: ActivityMode = .walking

    static let placeholder = StreakEntry(date: .now, streak: 0)
}
