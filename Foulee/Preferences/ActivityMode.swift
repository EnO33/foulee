import Foundation

/// Which activity the user wants Foulée to support. Walking is the app's
/// original — and until now only — scope, so it stays the default: an
/// install that has never written the preference must keep behaving exactly
/// as it did before (issue #219).
///
/// No display label yet, unlike `ThemeMode`: the picker that would read one
/// arrives with the settings UI (issue #220). It can't ship early either —
/// a `label` nothing calls is a plain unused property, and the dead-code scan
/// fails the build on it. The conformances below survive the same scan because
/// they aren't plain properties: `id` satisfies an `Identifiable` requirement
/// and the cases are reachable through `Codable`, so Periphery retains them
/// even while #220 is still the only thing that would enumerate them.
enum ActivityMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case walking
    case running
    case both

    var id: String { rawValue }
}
