import Dependencies
import FouleeKit
import Foundation
import Testing
@testable import Foulee

/// The review request's memory across launches (issue #580).
@Suite("ReviewPromptStore")
struct ReviewPromptStoreTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let beforeRecord = ReviewProgress(streak: 4, bestStreak: 4, outings: 0)
    private let record = ReviewProgress(streak: 5, bestStreak: 5, outings: 0)

    private func defaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: "ReviewPromptStoreTests.\(name)"))
        defaults.removePersistentDomain(forName: "ReviewPromptStoreTests.\(name)")
        return defaults
    }

    private func launch(_ defaults: UserDefaults, version: String = "1.52", at date: Date? = nil) -> ReviewPromptStore {
        let store = withDependencies {
            $0.date = .constant(date ?? now)
        } operation: {
            ReviewPromptStore(defaults: defaults, version: version)
        }
        store.recordLaunch()
        return store
    }

    @Test("The first launch never asks, the second does")
    func firstLaunch() throws {
        let defaults = try defaults("firstLaunch")
        #expect(!launch(defaults).shouldRequest(from: beforeRecord, to: record))
        #expect(launch(defaults).shouldRequest(from: beforeRecord, to: record))
    }

    @Test("Asking once is remembered for the version, across launches")
    func oncePerVersion() throws {
        let defaults = try defaults("oncePerVersion")
        _ = launch(defaults)
        #expect(launch(defaults).shouldRequest(from: beforeRecord, to: record))
        #expect(!launch(defaults, at: now + 200 * 24 * 3600).shouldRequest(from: beforeRecord, to: record))
        #expect(launch(defaults, version: "1.53", at: now + 200 * 24 * 3600).shouldRequest(from: beforeRecord, to: record))
    }

    @Test("No moment, no request, and nothing recorded")
    func noMoment() throws {
        let defaults = try defaults("noMoment")
        _ = launch(defaults)
        let store = launch(defaults)
        #expect(!store.shouldRequest(from: record, to: record))
        #expect(store.shouldRequest(from: beforeRecord, to: record))
    }

    @Test("Finished outings are counted across launches")
    func outings() throws {
        let defaults = try defaults("outings")
        let store = launch(defaults)
        store.recordOuting()
        store.recordOuting()
        #expect(launch(defaults).outings == 2)
    }
}
