import Foundation

/// Plain bag describing an `HKWorkout` for the summary sheet —
/// keeps `HKWorkout` (non-`Sendable`, framework-specific) out of view code.
nonisolated public struct WorkoutSummary: Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var durationSeconds: TimeInterval
    public var distanceKm: Double
    public var activeCalories: Int
    /// Steps for the walk. From Foulée's own metadata for walks it recorded; 0
    /// for other sources (the detail then falls back to a window query).
    /// Defaulted so existing initialisers compile.
    public var steps: Int = 0
    /// Elevation gain (metres) from `HKMetadataKeyElevationAscended` — 0 when
    /// the source didn't record it. Defaulted so existing initialisers compile.
    public var elevationMeters: Double = 0
    /// Descent (metres) from `HKMetadataKeyElevationDescended` — 0 when the
    /// source didn't record it (issue #565). Never added to the climb.
    public var descentMeters: Double = 0
    /// "Foulée", "Forme", "Apple Watch", etc. — read from
    /// `HKWorkout.sourceRevision.source.name`.
    public var sourceName: String
    /// What the session was recorded as (issue #245).
    ///
    /// Defaulted to `.other` and **not** to `.walking`, though a walk is by far
    /// the commoner case: a call site that forgets this field then shows the
    /// neutral « Séance » instead of asserting a walk that may have been a run.
    /// Issue #223 is what a silent `.walking` default costs — it stamped every
    /// session the app had ever written, permanently.
    public var activity: RecordedActivity = .other
    /// Where this workout sits in a watch outing, when the watch said so
    /// (issue #316). Read by `OutingGrouping`, which ties legs back together.
    public var outing: OutingLeg?
    /// The workouts this row stands for, oldest first, when it is an outing
    /// regrouped from several legs (issue #317). Empty for an ordinary row.
    ///
    /// Kept rather than folded away: the detail (#318) and the map (#319) show
    /// the outing leg by leg.
    public var legs: [WorkoutSummary] = []

    public init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: TimeInterval,
        distanceKm: Double,
        activeCalories: Int,
        steps: Int = 0,
        elevationMeters: Double = 0,
        descentMeters: Double = 0,
        sourceName: String,
        activity: RecordedActivity = .other,
        outing: OutingLeg? = nil,
        legs: [WorkoutSummary] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.distanceKm = distanceKm
        self.activeCalories = activeCalories
        self.steps = steps
        self.elevationMeters = elevationMeters
        self.descentMeters = descentMeters
        self.sourceName = sourceName
        self.activity = activity
        self.outing = outing
        self.legs = legs
    }
}

nonisolated public extension WorkoutSummary {
    /// Every activity the row covers, in the order they were first done.
    ///
    /// One for an ordinary row. For a regrouped outing, each sport once:
    /// walk → run → walk → run is « Marche et course », not a list of four.
    var activities: [RecordedActivity] {
        legs.isEmpty ? [activity] : legs.map(\.activity).firstOccurrences
    }

    /// How the row names what was done: « Course », or « Marche et course » for
    /// an outing that changed sport — « Walk and run » in English. The list is
    /// joined in `Locale.app`, the language the labels are written in.
    var activityLabel: String {
        let labels = activities.enumerated().map { index, activity in
            index == 0 ? activity.label : activity.label.lowercased(with: .app)
        }
        guard labels.count > 1 else { return labels.first ?? activity.label }
        return labels.formatted(.list(type: .and).locale(.app))
    }

    /// « ↑ 120 m », or `nil` when the source wrote no climb (issue #534):
    /// absent, not « ↑ 0 m », which would read as a flat outing.
    var climbText: String? {
        elevationMeters >= 1 ? "↑ \(Int(elevationMeters.rounded()).groupedText()) m" : nil
    }

    /// The same climb as VoiceOver says it: « 120 mètres de montée », not
    /// « flèche vers le haut ».
    var climbSpokenText: String? {
        elevationMeters >= 1 ? kitText("\(Int(elevationMeters.rounded())) mètres de montée") : nil
    }

    /// « ↓ 115 m », or `nil` when the source wrote no descent (issue #565).
    var descentText: String? {
        descentMeters >= 1 ? "↓ \(Int(descentMeters.rounded()).groupedText()) m" : nil
    }

    /// « 115 mètres de descente », for VoiceOver.
    var descentSpokenText: String? {
        descentMeters >= 1 ? kitText("\(Int(descentMeters.rounded())) mètres de descente") : nil
    }

    /// « 08:00 → 08:41 » — the row, the detail and the bubbles all say it so.
    var timeRangeText: String { "\(startedAt.clockText) → \(endedAt.clockText)" }

    /// « de 08:00 à 08:41 », for VoiceOver, which reads the arrow as one.
    var timeRangeSpokenText: String { kitText("de \(startedAt.clockText) à \(endedAt.clockText)") }

    /// « 142 kcal », the row and the detail alike. A Garmin outing Santé
    /// doesn't have yet (#479) says « — kcal »: the watch doesn't send its
    /// energy, and 0 would read as a figure.
    var caloriesText: String {
        GarminPendingOutings.isPending(self) ? "— kcal" : "\(activeCalories) kcal"
    }

    /// The figure drawn next to the row: the sport's own, or the walk-and-run
    /// figure once an outing mixes them — what `ActivityGlyph.mixedCardio`
    /// stands for.
    var activityIcon: String {
        activities.count > 1 ? ActivityGlyph.mixedCardio : activity.icon
    }
}
