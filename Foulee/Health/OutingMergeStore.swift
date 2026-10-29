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
///
/// The list follows the user's other iPhones through iCloud's key-value store
/// (issue #617), as one set with its own stamp: the newer list wins whole, so a
/// separation travels as surely as a merge (`CloudSettingsSync`).
nonisolated enum OutingMergeStore {
    private static let key = "outings.merges"
    private static let modifiedAtKey = "outings.merges.modifiedAt"

    /// The merges still within reach of a read; older ones are dropped from
    /// the store on the way.
    static func read(now: Date = .now, from defaults: UserDefaults = .standard) -> [OutingMerge] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([OutingMerge].self, from: data) else { return [] }
        let kept = OutingMerges.kept(stored, now: now)
        // Dropped here only: every iPhone forgets the same merges on its own,
        // so this is no change to send.
        if kept != stored {
            write(kept, to: defaults)
        }
        return kept
    }

    /// Keeps `merges`, and sends them to `cloud` when there is one.
    static func write(
        _ merges: [OutingMerge],
        to defaults: UserDefaults = .standard,
        cloud: SettingsKeyValueStore? = nil,
        now: Date = .now
    ) {
        guard let data = try? JSONEncoder().encode(merges) else { return }
        defaults.set(data, forKey: key)
        guard let cloud else { return }
        CloudSettingsSync.localDidChange([key], local: defaults, cloud: cloud, now: now, stamp: modifiedAtKey)
    }

    /// Brings both sides to the newer list, at launch and whenever iCloud
    /// says another iPhone changed something. A list kept before this sync
    /// fills an empty cloud; an install that never merged sends nothing, so
    /// it cannot cover a list iCloud has not downloaded yet.
    @discardableResult
    static func syncWithCloud(
        _ cloud: SettingsKeyValueStore,
        defaults: UserDefaults = .standard
    ) -> CloudSettingsSync.Outcome {
        CloudSettingsSync.reconcile(
            [key],
            local: defaults,
            cloud: cloud,
            seeds: defaults.object(forKey: key) != nil,
            stamp: modifiedAtKey
        )
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
        write: { OutingMergeStore.write($0, cloud: NSUbiquitousKeyValueStore.default) }
    )

    /// For a screenshot capture, which must never reach a real account.
    static let localValue = OutingMergeClient(
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
