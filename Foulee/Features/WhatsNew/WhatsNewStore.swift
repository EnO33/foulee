import FouleeKit
import Foundation

/// The « Nouveautés » to show at this opening (issue #621), read from the
/// bundled `WhatsNew.json`, and the version last shown or skipped. The rule is
/// `WhatsNewRelease.toShow`.
final class WhatsNewStore {
    /// The screenshot mode's throwaway suite in a capture, so a capture leaves
    /// the real install's version alone.
    static let shared = WhatsNewStore(defaults: FouleeApp.preferencesDefaults)

    private let defaults: UserDefaults
    private let version: String
    private let releases: () -> [WhatsNewRelease]

    init(
        defaults: UserDefaults = .standard,
        version: String = AppVersion.marketing,
        releases: @escaping () -> [WhatsNewRelease] = WhatsNewStore.bundled
    ) {
        self.defaults = defaults
        self.version = version
        self.releases = releases
    }

    /// On the home's appearance: the release to show, if this version is
    /// notable and its screen not yet seen. A version with nothing to show
    /// counts as seen at once; one with a release, once its screen appears.
    func pending() -> WhatsNewRelease? {
        let lastSeen = defaults.string(forKey: Keys.lastSeenVersion)
        guard lastSeen != version else { return nil }
        let release = WhatsNewRelease.toShow(in: releases(), current: version, lastSeen: lastSeen)
        if release == nil { markSeen() }
        return release
    }

    /// The screen appeared, or must never: at the end of the onboarding, which
    /// already presents the app.
    func markSeen() {
        defaults.set(version, forKey: Keys.lastSeenVersion)
    }

    /// The app's `WhatsNew.json`. A file that fails to decode shows nothing:
    /// the app test on the bundled file is what catches it.
    nonisolated static func bundled() -> [WhatsNewRelease] {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? WhatsNewRelease.decode(data)) ?? []
    }

    private enum Keys {
        static let lastSeenVersion = "whatsNew.lastSeenVersion"
    }
}
