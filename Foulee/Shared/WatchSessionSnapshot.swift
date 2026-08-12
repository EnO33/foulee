import Foundation

/// The figures of a live session, as the Watch states them to the iPhone
/// (issue #278).
///
/// **A complete state, never a delta.** A delta that goes missing cannot be
/// recovered; a complete state that goes missing is corrected by the next one.
/// That matters more here than it would over most links, because the link is
/// not the bottleneck — HealthKit **caches** what a mirrored session sends and
/// wakes the iOS app *periodically*, potentially minutes apart. Everything sent
/// between two wakes is discarded, whatever it was.
///
/// Which is also why the screen must date its figures rather than claim to be
/// live. `sentAt` is not bookkeeping: it is the only honest thing the phone can
/// print next to a step count.
struct WatchSessionSnapshot: Codable, Equatable, Sendable {
    /// When the wrist stated these figures. Two snapshots can arrive out of
    /// order — HealthKit promises delivery, not sequence — so the reader keeps
    /// the newest and drops the rest.
    var sentAt: Date
    /// The **outing's** start, across legs. Not the current leg's: a change of
    /// sport opens a new session (issue #265), and a clock built on the leg
    /// would reset to zero every time the wearer broke into a run.
    var outingStartedAt: Date
    var activity: SessionActivity
    var steps: Int
    var distanceMeters: Double
    var activeCalories: Int
    var heartRate: Int?
    /// The outing is over.
    ///
    /// **The only mechanism that ends the display**, together with staleness.
    /// The obvious alternative — an `HKWorkoutType` observer in `.immediate` —
    /// is not one: since issue #265 it fires on *every* `finishWorkout()`, so
    /// it would announce the end of the outing at the first walk→run switch.
    var isEnded: Bool

    init(
        sentAt: Date,
        outingStartedAt: Date,
        activity: SessionActivity,
        steps: Int,
        distanceMeters: Double,
        activeCalories: Int,
        heartRate: Int?,
        isEnded: Bool
    ) {
        self.sentAt = sentAt
        self.outingStartedAt = outingStartedAt
        self.activity = activity
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.activeCalories = activeCalories
        self.heartRate = heartRate
        self.isEnded = isEnded
    }

    /// Tolerant by hand, because the two ends are **two apps that update
    /// separately**: a watch on a newer build talks to a phone on an older one
    /// for as long as the owner takes to install both.
    ///
    /// `activity` is the one that would otherwise throw rather than degrade —
    /// the synthesised decoder rejects a raw value it does not know, so a sport
    /// added later would make the whole snapshot undecodable and the phone
    /// would show nothing at all rather than a walk it half-understood.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sentAt = try container.decode(Date.self, forKey: .sentAt)
        outingStartedAt = try container.decode(Date.self, forKey: .outingStartedAt)
        activity = (try? container.decode(SessionActivity.self, forKey: .activity)) ?? .walking
        steps = try container.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? 0
        activeCalories = try container.decodeIfPresent(Int.self, forKey: .activeCalories) ?? 0
        heartRate = try container.decodeIfPresent(Int.self, forKey: .heartRate)
        isEnded = try container.decodeIfPresent(Bool.self, forKey: .isEnded) ?? false
    }

    /// Drawn by `MirroredWalkScreen` — the phone's only view of a distance it
    /// did not measure.
    var distanceKm: Double { distanceMeters / 1_000 }

    /// How long the outing has run, read at `date`.
    ///
    /// Derived from a **date**, not carried as a duration, so the phone's clock
    /// keeps ticking between two wakes instead of freezing on the last figure
    /// it was told. Same construction as `WatchWorkoutMetrics.elapsed(at:)`
    /// (issue #266) and for the same reason.
    func elapsed(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(outingStartedAt))
    }

    /// The outing's average pace at the instant the wrist stated these figures
    /// — « 6'10"/km » — or `nil` when there is not enough distance to divide
    /// (issue #298).
    ///
    /// **Read at `sentAt`, never at « now ».** The screen's clock keeps
    /// advancing between two wakes while the distance stays frozen at the last
    /// snapshot, so dividing a frozen distance by a growing duration would make
    /// the pace drift towards slow — a figure that degrades on its own
    /// precisely when the mirror has gone quiet, which is when someone looks at
    /// it.
    var averagePaceText: String? {
        elapsed(at: sentAt).paceText(overKm: distanceKm)
    }

    /// How old these figures are. What the screen has to say out loud rather
    /// than pretend away.
    func age(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(sentAt))
    }
}
