import SwiftUI

/// The colour each activity is drawn in, wherever an outing is broken down by
/// sport — the detail's timeline and heart-rate chart (issue #318), and the
/// maps to come (#319, #320).
///
/// One table for every surface, and SwiftUI-only so the watch can compile it
/// too: a walk drawn cyan on the phone and green on the wrist would make the
/// two screens disagree about the same outing.
///
/// **Blue against orange** because it is the pair that stays apart under the
/// commonest colour-vision deficiencies, where red against green collapses.
/// Bright in dark mode, deeper in light mode so they stay readable on white
/// (`ReadablePalette`, #599). And never the colour alone: every place that
/// paints a sport also names it, with a glyph or a label.
nonisolated enum ActivityPalette {
    static let walk = ReadablePalette.cyan
    static let run = ReadablePalette.orange
    static let hike = ReadablePalette.green
    /// A sport Foulée cannot name.
    static let neutral = Color.gray
}
