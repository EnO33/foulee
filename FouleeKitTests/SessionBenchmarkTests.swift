import Foundation
import Testing
@testable import FouleeKit

/// The figures an outing is measured by against the six months before it
/// (issue #526).
@Suite("Session benchmark")
struct SessionBenchmarkTests {
    private let calendar = Calendar.iso8601Monday

    /// Thursday 22 October 2026, 18 h: the outing measured, unless said.
    private var now: Date { day(2026, 10, 22, hour: 18) }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// `km` at `secondsPerKm`, from `start`.
    private func outing(
        _ activity: RecordedActivity = .walking,
        at start: Date,
        km: Double = 5,
        secondsPerKm: TimeInterval = 600,
        elevation: Double = 0,
        source: String = "Foulée"
    ) -> WorkoutSummary {
        let duration = km * secondsPerKm
        return WorkoutSummary(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(duration),
            durationSeconds: duration,
            distanceKm: km,
            activeCalories: 0,
            elevationMeters: elevation,
            sourceName: source,
            activity: activity
        )
    }

    // MARK: - Pace

    @Test("The usual pace is the distance-weighted average of the same sport")
    func averagePace() throws {
        let current = outing(at: now, secondsPerKm: 570)
        let history = [
            outing(at: day(2026, 9, 1), km: 10, secondsPerKm: 600),
            outing(at: day(2026, 8, 1), km: 2, secondsPerKm: 660),
            outing(.running, at: day(2026, 8, 2), secondsPerKm: 330)
        ]
        let benchmark = SessionBenchmark.make(for: current, among: history + [current], calendar: calendar)
        #expect(benchmark.outing == current)
        #expect(benchmark.activity == .walking)
        let pace = try #require(benchmark.pace)
        #expect(pace.current == 570)
        #expect(pace.sessions == 2)
        // (10 km × 600 s + 2 km × 660 s) / 12 km.
        #expect(pace.average == 610)
        #expect(pace.best == 600)
    }

    @Test("Six months back and no further, and nothing after the outing")
    func window() throws {
        let current = outing(at: now)
        let history = [
            outing(at: day(2026, 4, 23)),
            outing(at: day(2026, 4, 21)),
            outing(at: day(2026, 10, 23))
        ]
        let pace = try #require(SessionBenchmark.make(for: current, among: history, calendar: calendar).pace)
        #expect(pace.sessions == 1)
    }

    @Test("The trend sets the last four weeks against the rest of the window")
    func trend() throws {
        let current = outing(at: now, secondsPerKm: 560)
        let history = [
            outing(at: day(2026, 10, 10), secondsPerKm: 580),
            outing(at: day(2026, 8, 10), secondsPerKm: 620),
            outing(at: day(2026, 7, 10), secondsPerKm: 640)
        ]
        let pace = try #require(SessionBenchmark.make(for: current, among: history, calendar: calendar).pace)
        #expect(pace.recent == 570)
        #expect(pace.recentSessions == 2)
        #expect(pace.earlier == 630)
        #expect(pace.earlierSessions == 2)
    }

    @Test("No pace for a hike, a short outing, or an implausible one")
    func noPace() {
        let cases = [
            outing(.hiking, at: now),
            outing(at: now, km: 0.8),
            outing(at: now, secondsPerKm: 3_000)
        ]
        for current in cases {
            #expect(SessionBenchmark.make(for: current, among: [], calendar: calendar).pace == nil)
        }
    }

    @Test("An outing that changed sport is compared on nothing but volume")
    func mixedOuting() {
        var current = outing(at: now)
        current.legs = [outing(at: now), outing(.running, at: now.addingTimeInterval(1_500))]
        let benchmark = SessionBenchmark.make(for: current, among: [outing(at: day(2026, 9, 1))], calendar: calendar)
        #expect(benchmark.activity == nil)
        #expect(benchmark.pace == nil)
        #expect(benchmark.records == nil)
        #expect(benchmark.volume.outingsThisWeek == 1)
    }

    // MARK: - Records

    @Test("The records are the same sport's, the outing set aside")
    func records() throws {
        let current = outing(.hiking, at: now, km: 12, elevation: 600)
        let history = [
            outing(.hiking, at: day(2026, 9, 1), km: 9, elevation: 450),
            outing(.hiking, at: day(2026, 8, 1), km: 11, elevation: 300),
            outing(at: day(2026, 8, 2), km: 20)
        ]
        let records = try #require(SessionBenchmark.make(for: current, among: history + [current], calendar: calendar).records)
        #expect(records.sessions == 2)
        #expect(records.longestKm == 11)
        #expect(records.climbingSessions == 2)
        #expect(records.highestElevationMeters == 450)
        #expect(records.averageElevationMeters == 375)
    }

    /// Garmin Connect and Strava both write the same walk: one outing, not a
    /// record beaten by its own copy.
    @Test("A copy of the outing from another writer is the outing")
    func copyIsTheOuting() throws {
        let current = outing(at: now, km: 8)
        let copy = outing(at: now.addingTimeInterval(30), km: 8.1, source: "Strava")
        let records = try #require(SessionBenchmark.make(for: current, among: [copy], calendar: calendar).records)
        #expect(records.sessions == 0)
        #expect(records.longestKm == nil)
    }

    // MARK: - Volume

    @Test("The week and the month count every sport, up to the outing")
    func volume() {
        let current = outing(at: now, km: 5, secondsPerKm: 600)
        // 30 + 10 m before it this month; the 23rd's 100 m come after.
        let history = [
            outing(.running, at: day(2026, 10, 20), km: 6, secondsPerKm: 300, elevation: 30),
            outing(at: day(2026, 10, 23), km: 4, elevation: 100),
            outing(at: day(2026, 10, 14), km: 3, secondsPerKm: 600),
            outing(at: day(2026, 10, 2), km: 2, elevation: 10),
            outing(at: day(2026, 9, 10), km: 7, elevation: 25)
        ]
        let volume = SessionBenchmark.make(for: current, among: history, calendar: calendar).volume
        #expect(volume.outingsThisWeek == 2)
        #expect(volume.minutesThisWeek == 80)
        #expect(volume.minutesLastWeek == 30)
        #expect(volume.kmThisMonth == 16)
        #expect(volume.kmLastMonth == 7)
        #expect(volume.climbThisMonth == 40)
        #expect(volume.climbLastMonth == 25)
        #expect(volume.lastMonth == day(2026, 9, 1, hour: 0))
    }
}
