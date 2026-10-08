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
/// System colours, so each one already has its dark-mode variant. And never the
/// colour alone: every place that paints a sport also names it, with a glyph or
/// a label.
enum ActivityPalette {
    static let walk = Color.cyan
    static let run = Color.orange
    static let hike = Color.green
    /// A sport Foulée cannot name.
    static let neutral = Color.gray
}
