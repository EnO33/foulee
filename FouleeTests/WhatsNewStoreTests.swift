import FouleeKit
import Foundation
import Testing
import UIKit
@testable import Foulee

/// The « Nouveautés » after an update (issue #621): the bundled file, and
/// when the screen shows.
@Suite("What's new store")
struct WhatsNewStoreTests {
    private let release = WhatsNewRelease(version: "1.59", items: [])

    private func freshDefaults() throws -> UserDefaults {
        let suite = "whats-new-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore(_ defaults: UserDefaults, version: String, releases: [WhatsNewRelease]) -> WhatsNewStore {
        WhatsNewStore(defaults: defaults, version: version) { releases }
    }

    @Test("The bundled file decodes, every text in French and English, every icon a symbol")
    func bundledFile() throws {
        let url = try #require(Bundle.main.url(forResource: "WhatsNew", withExtension: "json"))
        let releases = try WhatsNewRelease.decode(Data(contentsOf: url))
        #expect(!releases.isEmpty)
        for item in releases.flatMap(\.items) {
            #expect(UIImage(systemName: item.icon) != nil, "\(item.icon)")
            for texts in [item.title, item.text] {
                #expect(Set(texts.keys) == ["fr", "en"], "\(texts)")
                #expect(!texts.values.contains(""), "\(texts)")
            }
        }
    }

    @Test("A notable version shows once")
    func showsOnce() throws {
        let defaults = try freshDefaults()
        let store = makeStore(defaults, version: "1.59", releases: [release])
        #expect(store.pending() == release)
        #expect(store.pending() == release)
        store.markSeen()
        #expect(store.pending() == nil)
    }

    @Test("A version with nothing to show counts as seen, so an older release stays hidden")
    func notNotable() throws {
        let defaults = try freshDefaults()
        #expect(makeStore(defaults, version: "1.60", releases: []).pending() == nil)
        #expect(makeStore(defaults, version: "1.61", releases: [release]).pending() == nil)
    }
}
