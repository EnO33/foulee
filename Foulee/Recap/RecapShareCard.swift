import Foundation

/// What a shared Bilan says (issue #410): the period's headline figures,
/// worded once so the image and the message sent with it never disagree.
///
/// Pure, built from a `Recap` — the same numbers the Bilan shows, nothing
/// recomputed. What it leaves out is deliberate: no route, no time of day,
/// no heart rate, no water. A picture sent to friends says how the period
/// went, not where or when the wearer goes out.
struct RecapShareCard: Equatable, Sendable {
    struct Stat: Equatable, Sendable, Identifiable {
        var label: String
        var value: String
        var icon: String

        var id: String { label }
    }

    /// « Ma semaine », « Mon mois ».
    var heading: String
    /// The Bilan's own title for the period: « Du 5 oct. au 11 oct. »,
    /// « Septembre 2026 ».
    var periodTitle: String
    /// « 8 h 30 ».
    var minutes: String
    /// « Objectif tenu 6 jours sur 7 », or `nil` when no day was planned.
    var goalLine: String?
    /// Distance, steps and outings, in that order.
    var stats: [Stat]
    /// « Lundi 5 oct. · 2 h 06 », or `nil` for a period without minutes.
    var bestDay: String?
    /// The text sent along with the image.
    var message: String

    init(recap: Recap) {
        let isWeek = recap.period.kind == .week
        heading = isWeek ? "Ma semaine" : "Mon mois"
        periodTitle = recap.period.title
        minutes = durationText(minutes: recap.totals.minutes)
        goalLine = Self.goalText(met: recap.goalDaysMet, planned: recap.goalDaysPlanned)
        let outings = recap.totals.outings
        stats = [
            Stat(label: "Distance", value: recap.totals.distanceKm.kmText(fractionDigits: 1), icon: FouleeIcon.distance),
            Stat(label: "Pas", value: recap.totals.steps.formattedFR, icon: FouleeIcon.footsteps),
            Stat(label: outings > 1 ? "Sorties" : "Sortie", value: "\(outings)", icon: "figure.walk")
        ]
        bestDay = recap.bestDay.map {
            "\(Self.dayFormatter.string(from: $0.date).capitalized(with: Self.french)) · \(durationText(minutes: $0.minutes))"
        }
        var message = "\(heading) sur Foulée : \(minutes) d'activité"
        if let goalLine { message += ", \(goalLine.prefix(1).lowercased())\(goalLine.dropFirst())" }
        self.message = message + "."
    }

    /// « Objectif tenu 6 jours sur 7 » — « jour » stays singular below two,
    /// as French has it.
    static func goalText(met: Int, planned: Int) -> String? {
        guard planned > 0 else { return nil }
        return "Objectif tenu \(met) jour\(met > 1 ? "s" : "") sur \(planned)"
    }

    private static let french = Locale(identifier: "fr_FR")

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = french
        formatter.dateFormat = "EEEE d MMM"
        return formatter
    }()
}

extension Recap {
    /// The days cut into Monday-first weeks of seven, `nil` before the first
    /// day and after the last — a month laid out as a calendar (issue #410).
    var calendarWeeks: [[Day?]] {
        let leading = days.first.map { (Calendar.iso8601Monday.component(.weekday, from: $0.date) + 5) % 7 } ?? 0
        var cells: [Day?] = Array(repeating: nil, count: leading) + days.map(Optional.some)
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}
