import SwiftUI

/// SF Symbol names used across screens, mapped to the design's icon vocabulary
/// (`walk`, `timer`, `flame`, …). Centralised so a future swap is one-line.
enum FouleeIcon {
    // The three activity figures are the one part of this table that surfaces
    // outside the app — the widgets draw them too, and they can't compile this
    // file (SwiftUI, DesignSystem). They live in `ActivityGlyph`, which is
    // Foundation-only, and are re-exported here so screens keep one icon table.
    static let walk = ActivityGlyph.walk
    static let run = ActivityGlyph.run
    /// Walk *and* run — the "les deux" option of the onboarding activity step.
    static let mixedCardio = ActivityGlyph.mixedCardio
    static let timer = "timer"
    static let check = "checkmark"
    static let footsteps = "shoe"
    static let distance = "location"
    static let flame = "flame.fill"
    static let bell = "bell.fill"
    static let sun = "sun.max.fill"
    static let heart = "heart.fill"
    static let play = "play.fill"
    static let pause = "pause.fill"
    static let stop = "stop.fill"
    static let location = "location.fill"
    static let sparkle = "sparkles"
    static let target = "target"
    static let watch = "applewatch"
}
