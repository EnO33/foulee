import SwiftUI

extension RecordedActivity {
    /// This activity's colour, from the table every surface shares (#318).
    var tint: Color {
        switch self {
        case .walking: ActivityPalette.walk
        case .running: ActivityPalette.run
        case .hiking: ActivityPalette.hike
        case .other: ActivityPalette.neutral
        }
    }
}
