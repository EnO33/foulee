import Foundation

/// The SF Symbol names that stand for an activity, in the one place every
/// target can compile.
///
/// Three surfaces outside the app draw an activity figure — the Série widget,
/// the Aujourd'hui widget and the Live Activity — and none of them compiles
/// `FouleeIcon`, which lives in `DesignSystem` and imports SwiftUI. Each had
/// its own `"figure.mixed.cardio"` literal, four copies of one symbol name
/// with nothing tying them together and no test pinning them: a typo in one of
/// them renders a blank box rather than failing the build, so the copies could
/// drift silently.
///
/// Foundation-only on purpose, so it can be listed in any target's sources —
/// the same move `ActivityMode+Icon.swift` made in the other direction. It is
/// the *names* that are shared here, not the design vocabulary: `FouleeIcon`
/// stays the app's single icon table and reads its activity figures from this
/// one (`FouleeIcon.walk`, `.run`, `.mixedCardio`), so a future swap is still
/// one line and now propagates past the app target.
enum ActivityGlyph {
    static let walk = "figure.walk"
    static let run = "figure.run"
    /// Walk *and* run — also the neutral stand-in wherever the surface knows a
    /// session is running but not which activity it is (the Live Activity, see
    /// issue #225).
    static let mixedCardio = "figure.mixed.cardio"
}
