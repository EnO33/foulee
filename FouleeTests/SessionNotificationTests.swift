import FouleeKit
import Foundation
import Testing
@testable import Foulee

/// What a session notification's tap opens (issue #530).
@Suite("Session notification")
struct SessionNotificationTests {
    private let calendar = Calendar.iso8601Monday

    private func day(_ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func notice(from start: Date, to end: Date) -> SessionNotice {
        SessionNotice(
            identifier: SessionNotice.prefix + UUID().uuidString,
            fireAt: end,
            title: "Marche enregistrée",
            body: "5,2 km en 48 min. Le détail t'attend.",
            startedAt: start,
            endedAt: end
        )
    }

    @Test("A tap opens the Bilan of the week on the outing announced")
    func roundTrip() throws {
        let notice = notice(from: day(22, hour: 9), to: day(22, hour: 10))
        let request = try #require(SessionNotification.request(
            identifier: notice.identifier,
            userInfo: SessionNotification.userInfo(for: notice)
        ))
        #expect(request.kind == .week)
        #expect(request.outing == DateInterval(start: notice.startedAt, end: notice.endedAt))
        // This week: the Bilan opens on the week in progress.
        #expect(request.period(at: day(23, hour: 8)) == nil)
        // Read next week: the week the outing was in.
        #expect(request.period(at: day(27, hour: 8)) == RecapPeriod.containing(notice.startedAt, .week))
    }

    @Test("Any other notification, or one without its outing, opens nothing")
    func otherNotifications() {
        let notice = notice(from: day(22, hour: 9), to: day(22, hour: 10))
        #expect(SessionNotification.request(identifier: "foulee.recap.week", userInfo: SessionNotification.userInfo(for: notice)) == nil)
        #expect(SessionNotification.request(identifier: notice.identifier, userInfo: [:]) == nil)
    }
}
