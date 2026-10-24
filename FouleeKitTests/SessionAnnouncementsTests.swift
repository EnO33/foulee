import Foundation
import Testing
@testable import FouleeKit

/// One notification per outing, however many times it shows up (issue #528).
@Suite("Session announcements")
struct SessionAnnouncementsTests {
    /// 2026-10-24 08:00 UTC.
    private static let anchor = Date(timeIntervalSince1970: 1_792_828_800)

    private func at(_ minutes: Double) -> Date {
        Self.anchor.addingTimeInterval(minutes * 60)
    }

    private func workout(
        _ activity: RecordedActivity = .walking,
        from start: Double,
        lasting minutes: Double,
        source: String = "Garmin Connect",
        outing: OutingLeg? = nil
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            startedAt: at(start),
            endedAt: at(start + minutes),
            durationSeconds: minutes * 60,
            distanceKm: minutes / 10,
            activeCalories: 0,
            sourceName: source,
            activity: activity,
            outing: outing
        )
    }

    private var register: SessionAnnouncements { SessionAnnouncements(since: at(0)) }

    @Test("A new outing is announced a minute after it is seen")
    func newOuting() throws {
        var register = register
        let walk = workout(from: 10, lasting: 40)
        let announcements = register.announce([walk], now: at(55))
        let announcement = try #require(announcements.first)
        #expect(announcements.count == 1)
        #expect(announcement.outing == walk)
        #expect(announcement.fireAt == at(56))
        #expect(register.entries.map(\.id) == [announcement.id])
    }

    @Test("Read again once its notification has gone, it is not announced twice")
    func readAgain() {
        var register = register
        let walk = workout(from: 10, lasting: 40)
        _ = register.announce([walk], now: at(55))
        #expect(register.announce([walk], now: at(57)).isEmpty)
    }

    /// The second leg lands within the minute: the notification is replaced,
    /// under the same identifier, by one for the whole outing.
    @Test("A leg landing before the notification goes replaces it")
    func laterLeg() throws {
        var register = register
        let outingID = OutingLeg(outingID: UUID(), index: 0)
        let walk = workout(from: 10, lasting: 20, source: "Foulée", outing: outingID)
        let first = try #require(register.announce([walk], now: at(31)).first)
        var runLeg = outingID
        runLeg.index = 1
        let run = workout(.running, from: 30, lasting: 15, source: "Foulée", outing: runLeg)
        let second = try #require(register.announce([walk, run], now: at(31.5)).first)
        #expect(second.id == first.id)
        #expect(second.outing.endedAt == at(45))
        #expect(second.fireAt == at(32.5))
        #expect(register.entries.count == 1)
    }

    @Test("Garmin Connect's copy of an outing the watch already sent is that outing")
    func garminCopy() {
        var register = register
        _ = register.announce([workout(from: 10, lasting: 40, source: "Montre Garmin")], now: at(51))
        let copy = workout(from: 10.2, lasting: 39.5)
        #expect(register.announce([copy], now: at(90)).isEmpty)
    }

    @Test("An outing recorded on this iPhone is never announced")
    func recordedHere() {
        var register = register
        register.markAnnounced(from: at(10), to: at(50))
        #expect(register.announce([workout(from: 10, lasting: 40, source: "Foulée")], now: at(51)).isEmpty)
    }

    @Test("Nothing ended before the register, nor more than six hours ago")
    func oldNews() {
        var register = SessionAnnouncements(since: at(60))
        #expect(register.announce([workout(from: 0, lasting: 40)], now: at(70)).isEmpty)
        #expect(register.announce([workout(from: 70, lasting: 30)], now: at(100 + 6 * 60 + 1)).isEmpty)
        #expect(register.announce([workout(from: 70, lasting: 30)], now: at(100 + 6 * 60)).count == 1)
    }

    @Test("Two outings of the day are two announcements")
    func twoOutings() {
        var register = register
        let morning = workout(from: 10, lasting: 30)
        let noon = workout(.running, from: 240, lasting: 30)
        #expect(register.announce([noon, morning], now: at(275)).map(\.outing) == [morning, noon])
    }

    @Test("Entries go after a week")
    func retention() {
        var register = register
        register.markAnnounced(from: at(0), to: at(30))
        _ = register.announce([], now: at(30 + 7 * 24 * 60 + 1))
        #expect(register.entries.isEmpty)
    }

    @Test("A notification avoids what the one before it said, not what it said itself")
    func angles() throws {
        var register = register
        let morning = try #require(register.announce([workout(from: 10, lasting: 30)], now: at(41)).first)
        #expect(register.angle(before: morning.id) == nil)
        register.record(.pace, for: morning.id)
        #expect(register.angle(before: morning.id) == nil)
        let noon = try #require(register.announce([workout(from: 240, lasting: 30)], now: at(271)).first)
        #expect(register.angle(before: noon.id) == .pace)
    }

    @Test("The register survives a round trip through JSON")
    func codable() throws {
        var register = register
        let walk = try #require(register.announce([workout(from: 10, lasting: 40)], now: at(55)).first)
        register.record(.trend, for: walk.id)
        let decoded = try JSONDecoder().decode(SessionAnnouncements.self, from: JSONEncoder().encode(register))
        #expect(decoded == register)
        #expect(decoded.entries.first?.angle == .trend)
        #expect(decoded.since == at(0))
    }
}
