import Foundation

/// A session saved on the Garmin watch, as the Foulée Monkey C app sends it
/// at the end (`summary`, ADR 0009, D2 and D6). The watch saved it into Garmin
/// Connect, which writes it to Santé later, sometimes much later: until then
/// this is the only trace of the outing on the phone (`GarminPendingOutings`).
///
/// The wire format is a Connect IQ message dictionary, shared verbatim with
/// `FouleeConnectIQ/source/SessionMessage.mc`:
///
///     { "t": "summary", "v", "sport", "start", "end", "duration",
///       "distanceM", "ascentM", "steps", "route" }
///
/// `start` and `end` are epoch seconds; `duration` is the recorded time in
/// seconds, pauses excluded, so it can be shorter than `end - start`. `route`
/// is flat `[lat, lon, lat, lon, …]` in degrees × 100 000, thinned on the
/// watch (`RouteMath.mc`); a watch on an older build sends none, nor any
/// `ascentM`, the climb in metres (#536).
nonisolated public struct GarminSessionSummary: Codable, Equatable, Sendable {
    public static let messageType = "summary"

    /// Latest schema version this build reads. A newer one is dropped whole.
    public static let schemaVersion = 1

    public var activity: SessionActivity
    /// Identifies the session: the watch records one at a time, so two
    /// deliveries with the same start are the same outing.
    public var startedAt: Date
    public var endedAt: Date
    public var durationSeconds: TimeInterval
    public var distanceMeters: Int
    /// The climb, in metres; 0 from a watch on an older build (#536).
    public var ascentMeters: Int
    public var steps: Int
    /// The outing's route, thinned on the watch. Empty without a fix.
    public var route: [Coordinate]

    public init(
        activity: SessionActivity,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: TimeInterval,
        distanceMeters: Int,
        ascentMeters: Int = 0,
        steps: Int,
        route: [Coordinate] = []
    ) {
        self.activity = activity
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.ascentMeters = ascentMeters
        self.steps = steps
        self.route = route
    }

    /// By hand for `route` and `ascentMeters`: summaries stored before they
    /// existed have neither, and must still read back.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activity = try container.decode(SessionActivity.self, forKey: .activity)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        durationSeconds = try container.decode(TimeInterval.self, forKey: .durationSeconds)
        distanceMeters = try container.decode(Int.self, forKey: .distanceMeters)
        ascentMeters = try container.decodeIfPresent(Int.self, forKey: .ascentMeters) ?? 0
        steps = try container.decode(Int.self, forKey: .steps)
        route = try container.decodeIfPresent([Coordinate].self, forKey: .route) ?? []
    }
}

nonisolated public extension GarminSessionSummary {
    nonisolated private enum Key {
        static let type = "t"
        static let version = "v"
        static let sport = "sport"
        static let start = "start"
        static let end = "end"
        static let duration = "duration"
        static let distance = "distanceM"
        static let ascent = "ascentM"
        static let steps = "steps"
        static let route = "route"
    }

    /// Fixed point on the wire: degrees × 100 000.
    private static let routeScale = 100_000.0

    /// Tolerant decoder for a raw Connect IQ message, in the manner of
    /// `GarminDailySnapshot.decode`:
    ///
    /// - another `t`, or a `v` this build doesn't know → rejected whole;
    /// - missing or non-positive `start`, or an `end` before it → rejected
    ///   (they place the outing on the clock);
    /// - an unknown `sport` → walking, the phone's own default;
    /// - missing or non-numeric metric → 0, negative → 0; a `duration` past
    ///   the wall clock is cut to it;
    /// - a malformed `route` costs the map, never the outing: it is dropped
    ///   whole.
    static func decode(_ message: Any) -> GarminSessionSummary? {
        guard let fields = message as? [AnyHashable: Any],
              fields[Key.type] as? String == messageType,
              ConnectIQField.integer(fields[Key.version]) == schemaVersion,
              let start = ConnectIQField.positiveDate(fields[Key.start]),
              let end = ConnectIQField.positiveDate(fields[Key.end]),
              end >= start else { return nil }

        let duration = TimeInterval(ConnectIQField.nonNegative(fields[Key.duration]))
        return GarminSessionSummary(
            activity: ConnectIQField.activity(fields[Key.sport]),
            startedAt: start,
            endedAt: end,
            durationSeconds: min(duration, end.timeIntervalSince(start)),
            distanceMeters: ConnectIQField.nonNegative(fields[Key.distance]),
            ascentMeters: ConnectIQField.nonNegative(fields[Key.ascent]),
            steps: ConnectIQField.nonNegative(fields[Key.steps]),
            route: route(fields[Key.route])
        )
    }

    /// Pairs of fixed-point degrees, each on the globe; anything else is no
    /// route at all, rather than a line through a point nobody walked.
    private static func route(_ value: Any?) -> [Coordinate] {
        guard let flat = value as? [Any], flat.count.isMultiple(of: 2) else { return [] }
        let degrees = flat.compactMap { ConnectIQField.finiteDouble($0) }.map { $0 / routeScale }
        guard degrees.count == flat.count else { return [] }
        let points = stride(from: 0, to: degrees.count, by: 2).map {
            Coordinate(latitude: degrees[$0], longitude: degrees[$0 + 1])
        }
        let onTheGlobe = points.allSatisfy { abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }
        return onTheGlobe ? points : []
    }

    /// The clock the outing covers, as the minute count reads a workout.
    var interval: ActiveMinutes.WorkoutInterval {
        ActiveMinutes.WorkoutInterval(start: startedAt, duration: durationSeconds)
    }
}
