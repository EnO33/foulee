/// The glyph that stands for an activity mode.
///
/// Lives in one place rather than in each view so the onboarding rows, the
/// Today ring and the Série widget can never drift apart (issue #222): a
/// runner who picked « Course » must not be shown a walking figure on the
/// screen they open every day, nor on the widget sitting on their Home Screen.
///
/// **Deliberately not on `ActivityMode` itself, and no longer in
/// `DesignSystem` either.** The enum is shared vocabulary — the watch, the
/// watch widget and now the iPhone widget compile it, because the sync payload
/// (issue #223) and the app-group snapshot both carry the mode — but only some
/// of those surfaces draw it. Folding the mapping into `ActivityMode.swift`
/// would ship it to two watch targets that show no activity figure at all;
/// keeping it a separate file means each target opts in by listing it. It sat
/// in `DesignSystem` while it read `FouleeIcon` (SwiftUI, app-only), which is
/// what kept the widget from using it; it reads `ActivityGlyph` now, so it is
/// Foundation-only and can travel.
///
/// The trap this shape exists to prevent is real: putting `icon` on the enum
/// made the phone build pass and the watch build fail, which is exactly what
/// happened when #222 and #223 were developed in parallel. The app target
/// picks this file up through its `Foulee/**` glob; every other target lists
/// its sources one by one (see Project.swift).
extension ActivityMode {
    var icon: String {
        switch self {
        case .walking: ActivityGlyph.walk
        case .running: ActivityGlyph.run
        case .both: ActivityGlyph.mixedCardio
        }
    }
}
