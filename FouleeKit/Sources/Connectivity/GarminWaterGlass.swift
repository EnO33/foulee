import Foundation

/// A glass drunk, noted at the Garmin watch with « J'ai bu » (`water`, ADR
/// 0009, D8). The watch cannot write to Santé: the phone writes the glass
/// there, with `syncIdentifier` in its metadata, and skips an identifier it
/// already wrote, so a glass sent again after a lost acknowledgement is never
/// counted twice.
///
/// The wire format is a Connect IQ message dictionary, shared verbatim with
/// `FouleeConnectIQ/source/WaterMessage.mc`:
///
///     { "t": "water", "v", "id", "at", "ml" }
///
/// `at` is epoch seconds; `id` is unique per glass on the watch.
nonisolated public struct GarminWaterGlass: Codable, Equatable, Sendable {
    public static let messageType = "water"

    /// Latest schema version this build reads. A newer one is dropped whole.
    public static let schemaVersion = 1

    /// More than any serving the phone offers: past it, the volume is a
    /// watch-side bug, not a drink, and Santé would keep it for good.
    static let maximumMilliliters = 2_000

    public var id: String
    public var loggedAt: Date
    public var milliliters: Int

    public init(id: String, loggedAt: Date, milliliters: Int) {
        self.id = id
        self.loggedAt = loggedAt
        self.milliliters = milliliters
    }

    /// What Santé knows the glass by (`HKMetadataKeySyncIdentifier`).
    public var syncIdentifier: String { "garmin.water.\(id)" }
}

nonisolated public extension GarminWaterGlass {
    nonisolated private enum Key {
        static let type = "t"
        static let version = "v"
        static let id = "id"
        static let loggedAt = "at"
        static let milliliters = "ml"
    }

    /// Strict, unlike the other decoders: a glass is written to Santé for good,
    /// so one that can't be identified, placed or measured is dropped whole
    /// rather than defaulted.
    static func decode(_ message: Any) -> GarminWaterGlass? {
        guard let fields = message as? [AnyHashable: Any],
              fields[Key.type] as? String == messageType,
              ConnectIQField.integer(fields[Key.version]) == schemaVersion,
              let id = fields[Key.id] as? String, !id.isEmpty,
              let loggedAt = ConnectIQField.positiveDate(fields[Key.loggedAt]),
              let milliliters = ConnectIQField.integer(fields[Key.milliliters]),
              (1...maximumMilliliters).contains(milliliters) else { return nil }
        return GarminWaterGlass(id: id, loggedAt: loggedAt, milliliters: milliliters)
    }

    /// `pending` with `glass` in it once: the watch resends until it hears the
    /// phone got it.
    static func adding(_ glass: GarminWaterGlass, to pending: [GarminWaterGlass]) -> [GarminWaterGlass] {
        pending.contains { $0.id == glass.id } ? pending : pending + [glass]
    }
}
