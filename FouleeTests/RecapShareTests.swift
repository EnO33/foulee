import FouleeKit
import Foundation
import Testing
@testable import Foulee

/// Sharing a Bilan as an image (issue #410).
@Suite("Recap sharing")
struct RecapShareTests {
    private let calendar = Calendar.iso8601Monday

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Monday 5 → Sunday 11 October 2026, Monday the best day.
    private func week(minutes: [Int] = [126, 70, 0, 80, 60, 90, 84], goalMinutes: Int = 30) -> Recap {
        let start = date(2026, 10, 5)
        let days = minutes.enumerated().map { offset, value in
            Recap.Day(
                date: calendar.date(byAdding: .day, value: offset, to: start)!,
                minutes: value,
                isPlanned: offset < 5
            )
        }
        let planned = days.filter(\.isPlanned)
        return Recap(
            period: RecapPeriod(kind: .week, start: start, end: date(2026, 10, 12)),
            totals: .init(minutes: 510, steps: 82_594, distanceKm: 70.94, calories: 6_506, outings: 12),
            previous: .init(minutes: 483, steps: 82_721, distanceKm: 70.1, calories: 6_000, outings: 13),
            days: days,
            goalMinutes: goalMinutes,
            goalDaysMet: planned.filter { $0.minutes >= goalMinutes }.count,
            goalDaysPlanned: planned.count
        )
    }

    @Test("A week reads as the Bilan does: its minutes, the goal days, the three figures")
    func weekCard() {
        let card = RecapShareCard(recap: week())
        #expect(card.heading == "Ma semaine")
        #expect(card.minutes == "8 h 30")
        #expect(card.goalLine == "Objectif tenu 4 jours sur 5")
        #expect(card.stats.map(\.label) == ["Distance", "Pas", "Sorties"])
        #expect(card.stats.map(\.value) == ["70,9 km", 82_594.groupedText(), "12"])
        #expect(card.bestDay == "Lundi 5 Oct. · 2 h 06")
        #expect(card.message == "Ma semaine sur Foulée : 8 h 30 d'activité, objectif tenu 4 jours sur 5.")
    }

    /// Only when the period climbed: a source that writes no climb must not
    /// put « 0 m » on the image (#539).
    @Test("The climb joins the figures, after the distance")
    func climbStat() {
        var recap = week()
        recap.totals.climbMeters = 1_249.6
        let card = RecapShareCard(recap: recap)
        #expect(card.stats.map(\.label) == ["Distance", "Dénivelé", "Pas", "Sorties"])
        #expect(card.stats[1].value == "\(1_250.groupedText()) m")
    }

    @Test("A month is « Mon mois »")
    func monthCard() {
        var recap = week()
        recap.period = RecapPeriod(kind: .month, start: date(2026, 9, 1), end: date(2026, 10, 1))
        let card = RecapShareCard(recap: recap)
        #expect(card.heading == "Mon mois")
        #expect(card.periodTitle == "Septembre 2026")
        #expect(card.message.hasPrefix("Mon mois sur Foulée : "))
    }

    @Test("« jour » stays singular below two, and no planned day means no goal line")
    func goalText() {
        #expect(RecapShareCard.goalText(met: 0, planned: 5) == "Objectif tenu 0 jour sur 5")
        #expect(RecapShareCard.goalText(met: 1, planned: 5) == "Objectif tenu 1 jour sur 5")
        #expect(RecapShareCard.goalText(met: 2, planned: 5) == "Objectif tenu 2 jours sur 5")
        #expect(RecapShareCard.goalText(met: 0, planned: 0) == nil)
    }

    /// Without a planned day, the message stops after the minutes rather than
    /// promising a goal nobody set.
    @Test("A period with no planned day leaves the goal out of the message")
    func noPlannedDay() {
        var recap = week()
        recap.goalDaysPlanned = 0
        recap.goalDaysMet = 0
        let card = RecapShareCard(recap: recap)
        #expect(card.goalLine == nil)
        #expect(card.message == "Ma semaine sur Foulée : 8 h 30 d'activité.")
    }

    @Test("One outing is « Sortie », and no minutes means no best day")
    func singularOuting() {
        var recap = week(minutes: [0, 0, 0, 0, 0, 0, 0])
        recap.totals.outings = 1
        let card = RecapShareCard(recap: recap)
        #expect(card.stats.last?.label == "Sortie")
        #expect(card.bestDay == nil)
    }

    /// October 2026 starts on a Thursday: three blanks, then 31 days, padded
    /// to whole weeks.
    @Test("A month is laid out in Monday-first weeks, blanks around it")
    func calendarWeeks() {
        let start = date(2026, 10, 1)
        let days = (0..<31).map {
            Recap.Day(date: calendar.date(byAdding: .day, value: $0, to: start)!, minutes: 0, isPlanned: true)
        }
        var recap = week()
        recap.days = days
        let weeks = recap.calendarWeeks
        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks[0].prefix(3).allSatisfy { $0 == nil })
        #expect(weeks[0][3]?.date == start)
        #expect(weeks.flatMap { $0 }.compactMap { $0 }.count == 31)
    }

    @Test("Each format renders at its pixel size", arguments: RecapShareFormat.allCases)
    func renders(format: RecapShareFormat) throws {
        let image = try #require(RecapShareRenderer.image(of: week(), as: format))
        #expect(image.size.width * image.scale == format.size.width * 3)
        #expect(image.size.height * image.scale == format.size.height * 3)
    }
}
