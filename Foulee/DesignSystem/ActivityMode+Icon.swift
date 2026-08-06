/// The glyph that stands for an activity mode.
///
/// Lives in one place rather than in each view so the onboarding rows and the
/// Today ring can never drift apart (issue #222): a runner who picked
/// « Course » must not be shown a walking figure on the screen they open every
/// day.
///
/// **Deliberately not on `ActivityMode` itself.** That type is shared
/// vocabulary — the watch and the watch widget compile it too, because the
/// sync payload carries the mode (issue #223) — and neither of those targets
/// compiles `FouleeIcon`. Putting the mapping on the enum made the phone build
/// pass and the watch build fail, which is exactly what happened when #222 and
/// #223 were developed in parallel. Keeping the presentation concern in an
/// iOS-only extension is what makes that mistake impossible rather than merely
/// unlikely: this file is picked up by the app target's `Foulee/**` glob, and
/// the other targets list their sources one by one.
extension ActivityMode {
    var icon: String {
        switch self {
        case .walking: FouleeIcon.walk
        case .running: FouleeIcon.run
        case .both: FouleeIcon.mixedCardio
        }
    }
}
