import Dependencies
import FouleeKit
import Foundation

/// The outings the wearer merged (issue #549). The rules are `OutingMerges`;
/// this only keeps the list.
///
/// **Persisted, in `UserDefaults.standard`**, like `GarminPendingOutingStore`:
/// no other process reads it, and the widgets see the outings through the
/// minutes the app publishes, which a merge does not change. Nothing here
/// reaches Santé.
nonisolated enum OutingMergeStore {
    private static let key = "outings.merges"

    /// The merges still within reach of a read; older ones are dropped from
    /// the store on the way.
    static func read(now: Date = .now, from defaults: UserDefaults = .standard) -> [OutingMerge] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([OutingMerge].self, from: data) else { return [] }
        let kept = OutingMerges.kept(stored, now: now)
        if kept != stored {
            write(kept, to: defaults)
        }
        return kept
    }

    static func write(_ merges: [OutingMerge], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(merges) else { return }
        defaults.set(data, forKey: key)
    }
}

/// `OutingMergeStore` as a dependency, so the Bilan's merge and separate can
/// be tested without touching the real defaults.
nonisolated struct OutingMergeClient: Sendable {
    var read: @Sendable () -> [OutingMerge]
    var write: @Sendable (_ merges: [OutingMerge]) -> Void
}

nonisolated extension OutingMergeClient: DependencyKey {
    static let liveValue = OutingMergeClient(
        read: { OutingMergeStore.read() },
        write: { OutingMergeStore.write($0) }
    )

    static let testValue = OutingMergeClient(
        read: { [] },
        write: { _ in }
    )
}

nonisolated extension DependencyValues {
    var outingMerges: OutingMergeClient {
        get { self[OutingMergeClient.self] }
        set { self[OutingMergeClient.self] = newValue }
    }
}
