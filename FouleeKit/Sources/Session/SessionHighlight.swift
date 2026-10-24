import Foundation

/// The one line an outing is announced with (issue #527): the most
/// encouraging thing its `SessionBenchmark` can truthfully say.
///
/// In order: a record, a pace better than usual, a climb bigger than usual,
/// a pace getting better, the distance or the climb of the month, the
/// regularity of the week — and, when none applies, the outing itself. The
/// climb counts as much as the distance: a hilly walk is an effort the pace
/// alone would hide. **Never a slower pace**: an outing that says nothing good on one
/// angle is told on the next, down to its own figures.
nonisolated struct SessionHighlight: Equatable, Sendable {
    /// What the line is about. The notification after this one avoids it
    /// when another angle applies, so two outings in a row don't read the
    /// same.
    nonisolated enum Angle: String, Sendable {
        case record
        case pace
        case climb
        case trend
        case regularity
        case arrival
    }

    var angle: Angle
    var title: String
    var body: String

    /// Fewer earlier outings than this, and « the usual » is a guess.
    static let minimumSessions = 3
    /// The least gain on the usual pace worth stating: 2 %.
    static let minimumPaceGain = 0.02
    /// Below this, a climb is the lie of the land, not an effort.
    static let minimumClimbMeters = 30.0
    /// A climb a quarter above the usual one, and 20 m at least, is worth
    /// saying.
    static let minimumClimbGain = 0.25

    /// The line for `benchmark`, avoiding `previous` when another angle
    /// applies.
    ///
    /// A record is news and always told, whatever came before. The outing's
    /// own figures never displace an angle for being new: told twice, a
    /// faster walk still encourages more than a plain « recorded ».
    static func pick(for benchmark: SessionBenchmark, avoiding previous: Angle? = nil) -> SessionHighlight {
        let candidates = [
            record(benchmark),
            pace(benchmark),
            climb(benchmark),
            trend(benchmark),
            month(benchmark),
            monthClimb(benchmark),
            week(benchmark)
        ].compactMap { $0 }
        if let record = candidates.first(where: { $0.angle == .record }) { return record }
        return candidates.first { $0.angle != previous } ?? candidates.first ?? arrival(benchmark)
    }

    // MARK: - Angles

    /// The longest, the biggest climb, the fastest: the climb first for a
    /// hike, which is told by it.
    private static func record(_ benchmark: SessionBenchmark) -> SessionHighlight? {
        guard let activity = benchmark.activity, let records = benchmark.records else { return nil }
        let distance = distanceRecord(benchmark, records)
        let climb = climbRecord(benchmark, records)
        let ordered = activity == .hiking ? [climb, distance] : [distance, climb]
        return (ordered + [paceRecord(benchmark)]).compactMap { $0 }.first
    }

    private static func distanceRecord(_ benchmark: SessionBenchmark, _ records: SessionBenchmark.Records) -> SessionHighlight? {
        guard let activity = benchmark.activity, records.sessions >= minimumSessions,
              let longest = records.longestKm, benchmark.outing.distanceKm - longest >= 0.1 else { return nil }
        return SessionHighlight(
            angle: .record,
            title: "Ta plus longue \(activity.noun) depuis 6 mois",
            body: "\(km(benchmark.outing.distanceKm)) aujourd'hui. La précédente faisait \(km(longest))."
        )
    }

    private static func climbRecord(_ benchmark: SessionBenchmark, _ records: SessionBenchmark.Records) -> SessionHighlight? {
        let climb = benchmark.outing.elevationMeters
        guard let activity = benchmark.activity, records.climbingSessions >= minimumSessions,
              let highest = records.highestElevationMeters,
              climb >= minimumClimbMeters, climb - highest >= 10 else { return nil }
        return SessionHighlight(
            angle: .record,
            title: activity == .hiking
                ? "Ton plus gros dénivelé depuis 6 mois"
                : "Ta \(activity.noun) la plus vallonnée depuis 6 mois",
            body: "\(meters(climb)) de dénivelé aujourd'hui. Le précédent record : \(meters(highest))."
        )
    }

    private static func paceRecord(_ benchmark: SessionBenchmark) -> SessionHighlight? {
        guard let activity = benchmark.activity, let pace = benchmark.pace, pace.sessions >= minimumSessions,
              let best = pace.best, let average = pace.average,
              seconds(pace.current) < seconds(best) else { return nil }
        return SessionHighlight(
            angle: .record,
            title: "Ta \(activity.noun) la plus rapide depuis 6 mois",
            body: "\(paceFigure(pace.current)) de moyenne, \(seconds(average) - seconds(pace.current)) s de mieux que d'habitude."
        )
    }

    private static func pace(_ benchmark: SessionBenchmark) -> SessionHighlight? {
        guard let pace = benchmark.pace, pace.sessions >= minimumSessions,
              let average = pace.average, isBetter(pace.current, than: average) else { return nil }
        return SessionHighlight(
            angle: .pace,
            title: "Plus rapide que d'habitude",
            body: "\(paceFigure(pace.current)), contre \(paceFigure(average)) en moyenne ces 6 derniers mois."
        )
    }

    private static func climb(_ benchmark: SessionBenchmark) -> SessionHighlight? {
        let climb = benchmark.outing.elevationMeters
        guard let records = benchmark.records, records.climbingSessions >= minimumSessions,
              let average = records.averageElevationMeters, climb >= minimumClimbMeters,
              climb >= average * (1 + minimumClimbGain), climb - average >= 20 else { return nil }
        return SessionHighlight(
            angle: .climb,
            title: "Plus de dénivelé que d'habitude",
            body: "\(meters(climb)) de dénivelé, contre \(meters(average)) en moyenne ces 6 derniers mois."
        )
    }

    private static func trend(_ benchmark: SessionBenchmark) -> SessionHighlight? {
        guard let activity = benchmark.activity, let pace = benchmark.pace,
              pace.recentSessions >= 2, pace.earlierSessions >= minimumSessions,
              let recent = pace.recent, let earlier = pace.earlier,
              isBetter(recent, than: earlier) else { return nil }
        return SessionHighlight(
            angle: .trend,
            title: "Ça progresse",
            body: "Depuis un mois, \(activity.verb) \(seconds(earlier) - seconds(recent)) s/km plus vite qu'avant."
        )
    }

    private static func month(_ benchmark: SessionBenchmark) -> SessionHighlight? {
        let volume = benchmark.volume
        guard volume.kmLastMonth > 0, volume.kmThisMonth > volume.kmLastMonth else { return nil }
        return SessionHighlight(
            angle: .regularity,
            title: "Ton mois dépasse déjà le précédent",
            body: "\(wholeKm(volume.kmThisMonth)) depuis le 1er, contre \(wholeKm(volume.kmLastMonth)) en \(monthName(volume.lastMonth))."
        )
    }

    private static func monthClimb(_ benchmark: SessionBenchmark) -> SessionHighlight? {
        let volume = benchmark.volume
        guard volume.climbLastMonth > 0, volume.climbThisMonth >= 100,
              volume.climbThisMonth > volume.climbLastMonth else { return nil }
        return SessionHighlight(
            angle: .climb,
            title: "Ton mois grimpe plus que le précédent",
            body: "\(meters(volume.climbThisMonth)) de dénivelé depuis le 1er, "
                + "contre \(meters(volume.climbLastMonth)) en \(monthName(volume.lastMonth))."
        )
    }

    private static func week(_ benchmark: SessionBenchmark) -> SessionHighlight? {
        let volume = benchmark.volume
        guard volume.outingsThisWeek >= 2 else { return nil }
        let total = durationText(minutes: volume.minutesThisWeek)
        let lastWeek = volume.minutesLastWeek
        let body = if lastWeek > 0, lastWeek < volume.minutesThisWeek {
            "Déjà \(total) cette semaine, plus que toute la semaine dernière."
        } else if lastWeek > 0, lastWeek == volume.minutesThisWeek {
            "Déjà \(total) cette semaine, autant que toute la semaine dernière."
        } else {
            "Déjà \(total) cette semaine."
        }
        return SessionHighlight(angle: .regularity, title: "\(volume.outingsThisWeek)ᵉ sortie de la semaine", body: body)
    }

    /// The outing itself: it arrived, and here is what it was.
    private static func arrival(_ benchmark: SessionBenchmark) -> SessionHighlight {
        let outing = benchmark.outing
        let minutes = durationText(minutes: Int((outing.durationSeconds / 60).rounded()))
        var figures = outing.distanceKm >= 0.05 ? "\(km(outing.distanceKm)) en \(minutes)" : minutes
        if outing.elevationMeters >= 10 {
            figures += ", \(meters(outing.elevationMeters)) de dénivelé"
        }
        return SessionHighlight(
            angle: .arrival,
            title: benchmark.activity?.recordedLabel ?? "Sortie enregistrée",
            body: "\(figures). Le détail t'attend."
        )
    }

    // MARK: - Figures

    /// Faster by at least `minimumPaceGain`, and by a second the text shows.
    private static func isBetter(_ pace: TimeInterval, than reference: TimeInterval) -> Bool {
        pace <= reference * (1 - minimumPaceGain) && seconds(pace) < seconds(reference)
    }

    /// Whole seconds, as the text states them: a gain is the difference of
    /// two figures the reader sees.
    private static func seconds(_ pace: TimeInterval) -> Int {
        Int(pace.rounded())
    }

    private static func paceFigure(_ pace: TimeInterval) -> String {
        paceText(secondsPerKm: pace, roundedTo: 1)
    }

    private static func km(_ value: Double) -> String {
        value.kmText(fractionDigits: 1)
    }

    private static func wholeKm(_ value: Double) -> String {
        "\(Int(value.rounded())) km"
    }

    private static func meters(_ value: Double) -> String {
        "\(Int(value.rounded()).formattedFR) m"
    }

    private static func monthName(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "LLLL"
        return formatter
    }()
}

nonisolated private extension RecordedActivity {
    /// « Ta plus longue marche » — every sport Foulée names is feminine.
    var noun: String {
        switch self {
        case .walking: "marche"
        case .running: "course"
        case .hiking: "randonnée"
        case .other: "sortie"
        }
    }

    /// « tu marches 15 s/km plus vite ». Only paced sports reach it.
    var verb: String {
        switch self {
        case .running: "tu cours"
        default: "tu marches"
        }
    }

    var recordedLabel: String {
        "\(label) enregistrée"
    }
}
