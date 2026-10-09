import SwiftUI

extension SessionActivity {
    /// This activity's colour, from the table both devices draw with (#318,
    /// #320, #334): an outing must not change colours between the wrist, the
    /// mirrored map and the detail screen.
    var tint: Color {
        switch self {
        case .walking: ActivityPalette.walk
        case .running: ActivityPalette.run
        }
    }
}
