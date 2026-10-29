import Foundation

/// What the settings sync reads and writes: the defaults on one side, iCloud's
/// key-value store on the other. Both already have these three methods.
nonisolated public protocol SettingsKeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

nonisolated extension UserDefaults: SettingsKeyValueStore {}
nonisolated extension NSUbiquitousKeyValueStore: SettingsKeyValueStore {}

/// Keeps the user's settings the same on every iPhone of one iCloud account
/// (issue #616), with no server of ours: Apple's key-value store carries them.
///
/// The settings move as one set, stamped with the time of their last change.
/// The newer set wins whole: two devices edited apart end with the settings of
/// the one edited last, never a mix of both.
nonisolated public enum CloudSettingsSync {
    /// When the set was last changed by hand, in seconds since 1970, on both
    /// sides. Absent locally until the first change, or the first sync.
    public static let modifiedAtKey = "preferences.modifiedAt"

    public enum Outcome: Equatable, Sendable {
        /// The cloud's set replaced the local one: whoever shows the
        /// settings has to read them again.
        case pulled
        case pushed
        case unchanged
    }

    /// A setting was changed on this device: stamp the set and send it.
    public static func localDidChange(
        _ keys: [String],
        local: SettingsKeyValueStore,
        cloud: SettingsKeyValueStore,
        now: Date
    ) {
        local.set(now.timeIntervalSince1970, forKey: modifiedAtKey)
        copy(keys, from: local, to: cloud)
    }

    /// Brings both sides to the newer set, at launch and whenever iCloud says
    /// another device changed something.
    ///
    /// - Parameter seeds: whether a set never stamped may still fill an empty
    ///   cloud. True for an install that went through onboarding before this
    ///   sync existed, so that its settings reach the next iPhone; false for a
    ///   new one, whose untouched defaults must not cover a set iCloud has not
    ///   downloaded yet. A seeded set carries the oldest stamp, so any real
    ///   change beats it.
    public static func reconcile(
        _ keys: [String],
        local: SettingsKeyValueStore,
        cloud: SettingsKeyValueStore,
        seeds: Bool
    ) -> Outcome {
        let localStamp = local.object(forKey: modifiedAtKey) as? Double
        let cloudStamp = cloud.object(forKey: modifiedAtKey) as? Double
        switch (localStamp, cloudStamp) {
        case (.none, .some):
            copy(keys, from: cloud, to: local)
            return .pulled
        case let (.some(mine), .some(theirs)) where theirs > mine:
            copy(keys, from: cloud, to: local)
            return .pulled
        case (.some, .none):
            copy(keys, from: local, to: cloud)
            return .pushed
        case let (.some(mine), .some(theirs)) where mine > theirs:
            copy(keys, from: local, to: cloud)
            return .pushed
        case (.none, .none) where seeds:
            local.set(0.0, forKey: modifiedAtKey)
            copy(keys, from: local, to: cloud)
            return .pushed
        default:
            return .unchanged
        }
    }

    /// Copies every key and the stamp; a key missing on one side is removed
    /// on the other, so a setting back to its default stays at its default.
    private static func copy(
        _ keys: [String],
        from source: SettingsKeyValueStore,
        to destination: SettingsKeyValueStore
    ) {
        for key in keys + [modifiedAtKey] {
            if let value = source.object(forKey: key) {
                destination.set(value, forKey: key)
            } else {
                destination.removeObject(forKey: key)
            }
        }
    }
}
