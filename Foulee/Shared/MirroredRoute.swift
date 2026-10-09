import Foundation

/// One stretch of a mirrored outing's route, in the sport it was done as
/// (issue #334).
///
/// What the wrist sends the phone so the outing it mirrors can be drawn on a
/// map, coloured by portion like the watch's « Plan » page (#320) and the
/// detail (#319). It rides in `WatchSessionSnapshot`, so it shares its rule:
/// **a complete route, never a delta** — a delta lost between two HealthKit
/// wakes could never be recovered, a complete route is corrected by the next.
struct MirroredRoutePortion: Equatable, Sendable {
    var activity: SessionActivity
    var coordinates: [Coordinate]

    /// Decimal places kept per degree: 5 is about a metre, finer than any
    /// wrist GPS fix and the threshold past which digits are only bytes.
    static let precision = 1e5
}

extension MirroredRoutePortion: Codable {
    private enum CodingKeys: String, CodingKey {
        case activity
        /// `[lat0, lon0, lat1, lon1, …]`, each rounded to `precision`.
        case points
    }

    /// Tolerant like the snapshot around it: the two ends are two apps that
    /// update separately, and a sport this build cannot name is still a route
    /// worth drawing. A trailing odd value is dropped rather than failing the
    /// whole snapshot.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activity = (try? container.decode(SessionActivity.self, forKey: .activity)) ?? .walking
        let flat = try container.decodeIfPresent([Double].self, forKey: .points) ?? []
        coordinates = stride(from: 0, to: flat.count - 1, by: 2).map {
            Coordinate(latitude: flat[$0], longitude: flat[$0 + 1])
        }
    }

    /// A flat array of rounded numbers: about half the bytes of
    /// `{"latitude":…,"longitude":…}` objects, on a payload that is resent
    /// whole every few seconds for as long as the outing lasts.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activity, forKey: .activity)
        let rounded = coordinates.flatMap { [Self.rounded($0.latitude), Self.rounded($0.longitude)] }
        try container.encode(rounded, forKey: .points)
    }

    private static func rounded(_ degrees: Double) -> Double {
        (degrees * precision).rounded() / precision
    }
}

extension Array where Element == MirroredRoutePortion {
    /// Whether there is a line to draw: two points in at least one portion.
    /// The phone offers a map only then (issue #334).
    var isDrawable: Bool {
        contains { $0.coordinates.count >= 2 }
    }
}
