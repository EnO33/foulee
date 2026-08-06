import SwiftUI

/// SF Symbol names used across screens, mapped to the design's icon vocabulary
/// (`walk`, `timer`, `flame`, …). Centralised so a future swap is one-line.
enum FouleeIcon {
    static let walk = "figure.walk"
    static let run = "figure.run"
    /// Walk *and* run — the "les deux" option of the onboarding activity step.
    static let mixedCardio = "figure.mixed.cardio"
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
