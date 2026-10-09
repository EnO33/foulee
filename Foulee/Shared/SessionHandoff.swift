import Foundation

/// A walk the phone is measuring right now, as the wrist is told (issue #335).
///
/// All the watch needs to offer « Reprendre la séance de l'iPhone »: that
/// there is one, and since when. Nothing it measured — the wrist only learns
/// the figures if it actually takes over, from the `SessionHandoff` it gets
/// back.
struct PhoneSessionStatus: Codable, Equatable, Sendable {
    var startedAt: Date
}

/// An outing the phone stops measuring and the wrist carries on (issue #335).
///
/// There is no API to move a workout session from the phone to the watch — the
/// mirror only goes the other way (ADR 0003). So the outing is cut in two the
/// way a change of sport already cuts it on the wrist (ADR 0002, D7): the
/// phone saves its stretch as **leg 0**, the watch opens **leg 1** of the same
/// outing, and `OutingLeg` ties the two workouts back together in the history.
struct SessionHandoff: Codable, Equatable, Sendable {
    /// What the phone measured, already saved as leg 0 of the outing.
    struct Leg: Equatable, Sendable {
        var activity: SessionActivity
        var start: Date
        var end: Date
        var steps: Int
        var distanceMeters: Double
        var activeCalories: Int
    }

    /// Shared by every leg of the outing: drawn by the phone, kept by the wrist.
    var outingID: UUID
    var phoneLeg: Leg

    /// The phone's stretch is leg 0; the wrist carries on at 1.
    static let continuingLegIndex = 1
    /// How long a handoff sent ahead of `startWatchApp` stays worth taking up.
    /// The watch app wakes within seconds; past two minutes, a handoff that was
    /// never collected belongs to an outing nobody is still out on.
    static let freshness: TimeInterval = 120

    /// When the phone stopped measuring — where the wrist's leg begins.
    var handedOverAt: Date { phoneLeg.end }

    /// The leg the wrist opens.
    var continuingLeg: OutingLeg {
        OutingLeg(outingID: outingID, index: Self.continuingLegIndex)
    }

    func isFresh(at now: Date) -> Bool {
        now.timeIntervalSince(handedOverAt) <= Self.freshness
    }
}

extension SessionHandoff.Leg: Codable {
    private enum CodingKeys: String, CodingKey {
        case activity, start, end, steps, distanceMeters, activeCalories
    }

    /// Tolerant like every payload between the two apps, which update
    /// separately: a sport this build cannot name is carried on as a walk.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activity = (try? container.decode(SessionActivity.self, forKey: .activity)) ?? .walking
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        steps = try container.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? 0
        activeCalories = try container.decodeIfPresent(Int.self, forKey: .activeCalories) ?? 0
    }
}

/// The WatchConnectivity keys of the handoff (issue #335). One spelling, read
/// by both apps.
enum SessionHandoffKey {
    /// Application context: the phone's walk in progress, if any.
    static let phoneSession = "phoneSession"
    /// Application context, or a message reply: the handoff itself.
    static let handoff = "handoff"
    /// Message from the wrist: « stop and hand over ».
    static let request = "handoffRequest"
}
