import Foundation
import Testing
@testable import FouleeKit

/// The one line an outing is announced with (issue #527).
@Suite("Session highlight")
struct SessionHighlightTests {
    let calendar = Calendar.iso8601Monday

    var start: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 18))!
    }

    var september: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
    }

    func outing(
        _ activity: RecordedActivity = .walking,
        km: Double = 5,
        minutes: Double = 50,
        elevation: Double = 0
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(minutes * 60),
            durationSeconds: minutes * 60,
            distanceKm: km,
            activeCalories: 0,
            elevationMeters: elevation,
            sourceName: "Garmin Connect",
            activity: activity
        )
    }

    func volume(
        outings: Int = 1,
        minutes: Int = 50,
        lastWeek: Int = 0,
        km: Double = 5,
        lastMonth: Double = 0,
        climb: Double = 0,
        climbLastMonth: Double = 0
    ) -> SessionBenchmark.Volume {
        SessionBenchmark.Volume(
            outingsThisWeek: outings,
            minutesThisWeek: minutes,
            minutesLastWeek: lastWeek,
            kmThisMonth: km,
            kmLastMonth: lastMonth,
            climbThisMonth: climb,
            climbLastMonth: climbLastMonth,
            lastMonth: september
        )
    }

    func records(
        sessions: Int = 5,
        longestKm: Double = 20,
        climbing: Int = 5,
        highestClimb: Double = 2_000,
        averageClimb: Double = 1_500
    ) -> SessionBenchmark.Records {
        SessionBenchmark.Records(
            sessions: sessions,
            longestKm: longestKm,
            climbingSessions: climbing,
            highestElevationMeters: highestClimb,
            averageElevationMeters: averageClimb
        )
    }

    func pace(
        _ current: TimeInterval,
        sessions: Int = 5,
        average: TimeInterval? = nil,
        best: TimeInterval? = nil,
        recent: TimeInterval? = nil,
        earlier: TimeInterval? = nil
    ) -> SessionBenchmark.Pace {
        SessionBenchmark.Pace(
            current: current,
            sessions: sessions,
            average: average,
            best: best,
            recent: recent,
            recentSessions: recent == nil ? 1 : 2,
            earlier: earlier,
            earlierSessions: earlier == nil ? 0 : 3
        )
    }

    func benchmark(
        _ outing: WorkoutSummary,
        pace: SessionBenchmark.Pace? = nil,
        records: SessionBenchmark.Records? = nil,
        volume: SessionBenchmark.Volume? = nil
    ) -> SessionBenchmark {
        SessionBenchmark(
            outing: outing,
            activity: outing.activities.count == 1 ? outing.activity : nil,
            pace: pace,
            records: records ?? self.records(),
            volume: volume ?? self.volume()
        )
    }

    // MARK: - Records

    @Test("A longer outing than any of six months is a record")
    func longest() {
        let records = records(sessions: 4, longestKm: 7.1)
        let highlight = SessionHighlight.pick(for: benchmark(outing(km: 8.4), records: records))
        #expect(highlight == SessionHighlight(
            angle: .record,
            title: "Ta plus longue marche depuis 6 mois",
            body: "8,4 km aujourd'hui. La précédente faisait 7,1 km."
        ))
    }

    @Test("A hike's record is its climb")
    func highestClimb() {
        let records = records(sessions: 3, longestKm: 15, climbing: 3, highestClimb: 450, averageClimb: 300)
        let highlight = SessionHighlight.pick(for: benchmark(outing(.hiking, km: 12, elevation: 620), records: records))
        #expect(highlight.title == "Ton plus gros dénivelé depuis 6 mois")
        #expect(highlight.body == "620 m de dénivelé aujourd'hui. Le précédent record : 450 m.")
    }

    @Test("A faster pace than any of six months is a record")
    func fastest() {
        let highlight = SessionHighlight.pick(for: benchmark(
            outing(.running),
            pace: pace(342, average: 360, best: 345)
        ))
        #expect(highlight == SessionHighlight(
            angle: .record,
            title: "Ta course la plus rapide depuis 6 mois",
            body: "5'42\"/km de moyenne, 18 s de mieux que d'habitude."
        ))
    }

    @Test("A record is told even right after another one")
    func recordRepeats() {
        let records = records(sessions: 4, longestKm: 7.1)
        let highlight = SessionHighlight.pick(
            for: benchmark(outing(km: 8.4), records: records, volume: volume(outings: 3)),
            avoiding: .record
        )
        #expect(highlight.angle == .record)
    }

    @Test("Under three earlier outings, nothing is a record")
    func tooFewForRecord() {
        let records = records(sessions: 2, longestKm: 3, climbing: 2, highestClimb: 10, averageClimb: 10)
        #expect(SessionHighlight.pick(for: benchmark(outing(km: 8.4), records: records)).angle == .arrival)
    }

    // MARK: - Pace and trend

    @Test("Two per cent faster than usual is worth saying")
    func fasterThanUsual() {
        let highlight = SessionHighlight.pick(for: benchmark(outing(), pace: pace(605, average: 632, best: 590)))
        #expect(highlight == SessionHighlight(
            angle: .pace,
            title: "Plus rapide que d'habitude",
            body: "10'05\"/km, contre 10'32\"/km en moyenne ces 6 derniers mois."
        ))
    }

    @Test("Faster by less than two per cent is not")
    func barelyFaster() {
        let highlight = SessionHighlight.pick(for: benchmark(outing(), pace: pace(625, average: 632, best: 590)))
        #expect(highlight.angle == .arrival)
    }

    @Test("A slower pace is never said: the next angle speaks")
    func slowerIsSilent() {
        let highlight = SessionHighlight.pick(for: benchmark(
            outing(),
            pace: pace(700, average: 632, best: 590),
            volume: volume(outings: 3, minutes: 105, lastWeek: 105)
        ))
        #expect(highlight == SessionHighlight(
            angle: .regularity,
            title: "3ᵉ sortie de la semaine",
            body: "Déjà 1 h 45 cette semaine, autant que toute la semaine dernière."
        ))
    }

    @Test("A pace getting better over four weeks is a trend")
    func improving() {
        let highlight = SessionHighlight.pick(for: benchmark(
            outing(),
            pace: pace(640, average: 632, best: 590, recent: 610, earlier: 625)
        ))
        #expect(highlight == SessionHighlight(
            angle: .trend,
            title: "Ça progresse",
            body: "Depuis un mois, tu marches 15 s/km plus vite qu'avant."
        ))
    }

    // MARK: - Regularity

    @Test("A month already past the one before")
    func monthAhead() {
        let highlight = SessionHighlight.pick(for: benchmark(outing(), volume: volume(km: 32.3, lastMonth: 28.1)))
        #expect(highlight == SessionHighlight(
            angle: .regularity,
            title: "Ton mois dépasse déjà le précédent",
            body: "32 km depuis le 1er, contre 28 km en septembre."
        ))
    }

    @Test("The week compares with the whole week before only when it holds up")
    func weekBodies() {
        func body(minutes: Int, lastWeek: Int) -> String {
            SessionHighlight.pick(for: benchmark(outing(), volume: volume(outings: 2, minutes: minutes, lastWeek: lastWeek))).body
        }
        #expect(body(minutes: 90, lastWeek: 60) == "Déjà 1 h 30 cette semaine, plus que toute la semaine dernière.")
        #expect(body(minutes: 45, lastWeek: 60) == "Déjà 45 min cette semaine.")
        #expect(body(minutes: 45, lastWeek: 0) == "Déjà 45 min cette semaine.")
    }

    // MARK: - Variety

    @Test("The angle of the last notification gives way to another")
    func avoidsPrevious() {
        let current = benchmark(
            outing(),
            pace: pace(605, average: 632, best: 590),
            volume: volume(outings: 2)
        )
        #expect(SessionHighlight.pick(for: current).angle == .pace)
        #expect(SessionHighlight.pick(for: current, avoiding: .pace).angle == .regularity)
    }

    @Test("With no other angle, the same one beats a plain arrival")
    func repeatsRatherThanFlatten() {
        let current = benchmark(outing(), pace: pace(605, average: 632, best: 590))
        #expect(SessionHighlight.pick(for: current, avoiding: .pace).angle == .pace)
    }

    // MARK: - Arrival

    @Test("Nothing to say but the outing: its figures")
    func arrival() {
        #expect(SessionHighlight.pick(for: benchmark(outing(km: 5.2, minutes: 48))) == SessionHighlight(
            angle: .arrival,
            title: "Marche enregistrée",
            body: "5,2 km en 48 min. Le détail t'attend."
        ))
    }

    @Test("An outing that changed sport, or without distance, still arrives")
    func arrivalVariants() {
        var mixed = outing(km: 0, minutes: 75)
        mixed.legs = [outing(), outing(.running)]
        let highlight = SessionHighlight.pick(for: benchmark(mixed))
        #expect(highlight.title == "Sortie enregistrée")
        #expect(highlight.body == "1 h 15. Le détail t'attend.")
    }
}
