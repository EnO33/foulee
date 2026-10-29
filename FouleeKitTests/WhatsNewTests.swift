import Foundation
import Testing
@testable import FouleeKit

/// Which « Nouveautés » the app shows after an update (issue #621).
@Suite("What's new")
struct WhatsNewTests {
    private func release(_ version: String) -> WhatsNewRelease {
        WhatsNewRelease(version: version, items: [])
    }

    private let releases = ["1.59", "1.61.0", "1.64"].map { WhatsNewRelease(version: $0, items: []) }

    @Test("The current version's release shows after an update")
    func currentRelease() {
        #expect(WhatsNewRelease.toShow(in: releases, current: "1.61.0", lastSeen: "1.60") == release("1.61.0"))
    }

    @Test("A version with no release shows nothing")
    func notNotable() {
        #expect(WhatsNewRelease.toShow(in: releases, current: "1.60", lastSeen: "1.59") == nil)
    }

    @Test("A release already seen never shows again")
    func alreadySeen() {
        #expect(WhatsNewRelease.toShow(in: releases, current: "1.61", lastSeen: "1.61.0") == nil)
        #expect(WhatsNewRelease.toShow(in: releases, current: "1.62", lastSeen: "1.61") == nil)
    }

    @Test("Skipping versions shows the newest release missed, never a later one")
    func skippedVersions() {
        #expect(WhatsNewRelease.toShow(in: releases, current: "1.63", lastSeen: "1.58") == release("1.61.0"))
        #expect(WhatsNewRelease.toShow(in: releases, current: "1.58", lastSeen: "1.57") == nil)
    }

    @Test("An install from before the screen gets the newest release up to its version")
    func noLastSeen() {
        #expect(WhatsNewRelease.toShow(in: releases, current: "1.59.0", lastSeen: nil) == release("1.59"))
        #expect(WhatsNewRelease.toShow(in: releases, current: "1.58", lastSeen: nil) == nil)
    }

    @Test("Versions compare number by number")
    func comparison() {
        #expect(WhatsNewRelease.compare("1.59", "1.59.0") == .orderedSame)
        #expect(WhatsNewRelease.compare("1.9", "1.10") == .orderedAscending)
        #expect(WhatsNewRelease.compare("2.0", "1.99.9") == .orderedDescending)
    }

    @Test("A release file decodes, and a text missing in a language falls back to French")
    func decoding() throws {
        let json = """
        [{ "version": "1.59", "items": [{
            "icon": "icloud",
            "title": { "fr": "Tes réglages te suivent", "en": "Your settings follow you" },
            "text": { "fr": "Sur chacun de tes iPhone." }
        }] }]
        """
        let item = try #require(WhatsNewRelease.decode(Data(json.utf8)).first?.items.first)
        #expect(item.icon == "icloud")
        #expect(item.title(in: "en") == "Your settings follow you")
        #expect(item.text(in: "en") == "Sur chacun de tes iPhone.")
        #expect(item.title(in: "de") == "Tes réglages te suivent")
    }
}
