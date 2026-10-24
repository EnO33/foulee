import Foundation
import Testing
@testable import FouleeKit

/// What an outing that just landed is announced with (issue #529).
@Suite("Session notice")
struct SessionNoticeTests {
    private let calendar = Calendar.iso8601Monday

    private func day(_ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func walk(on date: Date, km: Double, secondsPerKm: TimeInterval = 600) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            startedAt: date,
            endedAt: date.addingTimeInterval(km * secondsPerKm),
            durationSeconds: km * secondsPerKm,
            distanceKm: km,
            activeCalories: 0,
            sourceName: "Garmin Connect",
            activity: .walking
        )
    }

    @Test("A new outing gets its notice, told by its highlight")
    func notice() throws {
        let history = [walk(on: day(1, hour: 9), km: 4), walk(on: day(5, hour: 9), km: 5), walk(on: day(8, hour: 9), km: 6)]
        let today = walk(on: day(22, hour: 9), km: 8.4)
        var register = SessionAnnouncements(since: day(1, hour: 0))
        let notice = try #require(register.notices(for: history + [today], now: today.endedAt, calendar: calendar).first)
        #expect(notice.identifier.hasPrefix(SessionNotice.prefix))
        #expect(notice.fireAt == today.endedAt.addingTimeInterval(SessionAnnouncements.delay))
        #expect(notice.title == "Ta plus longue marche depuis 6 mois")
        #expect(notice.body == "8,4 km aujourd'hui. La précédente faisait 6,0 km.")
        #expect(notice.startedAt == today.startedAt)
        #expect(notice.endedAt == today.endedAt)
        #expect(register.entries.first?.angle == .record)
    }

    @Test("The next outing avoids what the last one said")
    func avoidsLastAngle() throws {
        // Usually 10'40"/km, once 9'40": 10'00" is better than usual, not a record.
        let history = zip(1...4, [580.0, 660, 660, 660]).map { walk(on: day($0, hour: 9), km: 5, secondsPerKm: $1) }
        var register = SessionAnnouncements(since: day(1, hour: 0))
        let morning = walk(on: day(20, hour: 9), km: 5, secondsPerKm: 600)
        let first = try #require(register.notices(for: history + [morning], now: morning.endedAt, calendar: calendar).first)
        #expect(first.title == "Plus rapide que d'habitude")
        let evening = walk(on: day(20, hour: 18), km: 5, secondsPerKm: 600)
        let workouts = history + [morning, evening]
        let second = try #require(register.notices(for: workouts, now: evening.endedAt, calendar: calendar).first)
        #expect(second.title == "2ᵉ sortie de la semaine")
    }
}
