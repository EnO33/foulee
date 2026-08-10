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
/// stays the app's single icon table and re-exports the neutral figure from
/// this one (`FouleeIcon.mixedCardio`), so a future swap is still one line and
/// now propagates past the app target. The walk and run names are read through
/// `ActivityMode.icon` instead — a screen that knows the mode asks the mode.
enum ActivityGlyph {
    static let walk = "figure.walk"
    static let run = "figure.run"
    /// Read-side only: Foulée never records a hike, but the 7-day résumé has
    /// listed them since #217 and now names them (#245).
    static let hike = "figure.hiking"
    /// Walk *and* run — also the neutral stand-in wherever the surface knows a
    /// session is running but not which activity it is (the Live Activity, see
    /// issue #225).
    static let mixedCardio = "figure.mixed.cardio"
}
