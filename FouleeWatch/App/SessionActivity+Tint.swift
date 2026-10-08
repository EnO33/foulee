import SwiftUI

extension SessionActivity {
    /// This activity's colour, from the table the phone draws with too
    /// (#318, #320): an outing must not change colours between the wrist and
    /// the detail screen.
    var tint: Color {
        switch self {
        case .walking: ActivityPalette.walk
        case .running: ActivityPalette.run
        }
    }
}
