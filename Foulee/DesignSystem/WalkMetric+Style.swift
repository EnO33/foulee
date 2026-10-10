import SwiftUI

/// Each metric's icon and colour, in one place (issue #366): the home's tiles,
/// the stats screen and the Bilan's comparison draw a metric in the colour of
/// its ring — steps purple like the outer ring, minutes green like the inner
/// one — so a number reads as the ring it fills.
extension WalkMetric {
    var icon: String {
        switch self {
        case .steps: FouleeIcon.footsteps
        case .minutes: FouleeIcon.timer
        case .distance: FouleeIcon.distance
        case .calories: FouleeIcon.flame
        }
    }

    /// From `MetricPalette`, which the watch shares (#372).
    var tint: Color {
        switch self {
        case .steps: MetricPalette.steps
        case .minutes: MetricPalette.minutes
        case .distance: MetricPalette.distance
        case .calories: MetricPalette.calories
        }
    }
}
