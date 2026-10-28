import FouleeKit
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

    /// The same colour on small text — a tile's label (issue #658): deeper
    /// in light mode, where `tint` falls under the 4.5:1 text needs.
    var labelTint: Color {
        switch self {
        case .steps: ReadablePalette.purpleText
        case .minutes: ReadablePalette.greenText
        case .distance: ReadablePalette.blueText
        case .calories: ReadablePalette.orangeText
        }
    }
}
