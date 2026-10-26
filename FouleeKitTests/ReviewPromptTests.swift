import Foundation
import Testing
@testable import FouleeKit

/// When Foulée asks for an App Store review (issue #580).
@Suite("Review prompt")
struct ReviewPromptTests {
    private let now = Date(timeIntervalSince1970: 1_716_940_800)
    private let day: TimeInterval = 24 * 60 * 60

    private func progress(_ streak: Int, best: Int? = nil, outings: Int = 0) -> ReviewProgress {
        ReviewProgress(streak: streak, bestStreak: best ?? streak, outings: outings)
    }

    @Test("Beating a record of two days or more is a moment")
    func streakRecord() {
        #expect(ReviewMoment.reached(from: progress(4, best: 4), to: progress(5)) == .streakRecord)
        #expect(ReviewMoment.reached(from: progress(2, best: 2), to: progress(3)) == .streakRecord)
    }

    @Test("Equalling the record, or a record of one day, is not")
    func notARecord() {
        #expect(ReviewMoment.reached(from: progress(3, best: 5), to: progress(4, best: 5)) == nil)
        #expect(ReviewMoment.reached(from: progress(1, best: 1), to: progress(2)) == nil)
    }

    @Test("Reaching seven days in a row is a moment, staying there is not")
    func weekStreak() {
        #expect(ReviewMoment.reached(from: progress(6, best: 9), to: progress(7, best: 9)) == .weekStreak)
        #expect(ReviewMoment.reached(from: progress(7, best: 9), to: progress(7, best: 9)) == nil)
        #expect(ReviewMoment.reached(from: progress(7, best: 9), to: progress(8, best: 9)) == nil)
    }

    @Test("The tenth outing is a moment, the eleventh is not")
    func outingsMilestone() {
        #expect(ReviewMoment.reached(from: progress(0, outings: 9), to: progress(0, outings: 10)) == .outingsMilestone)
        #expect(ReviewMoment.reached(from: progress(0, outings: 10), to: progress(0, outings: 11)) == nil)
    }

    @Test("A jump is a read catching up, not a moment")
    func jumps() {
        #expect(ReviewMoment.reached(from: progress(0, best: 0), to: progress(12)) == nil)
        #expect(ReviewMoment.reached(from: progress(0, best: 3), to: progress(7, best: 7)) == nil)
        #expect(ReviewMoment.reached(from: progress(0, outings: 0), to: progress(0, outings: 10)) == nil)
    }

    @Test("Never on the first launch")
    func firstLaunch() {
        #expect(!ReviewPromptHistory(isFirstLaunch: true).allowsRequest(version: "1.52", now: now))
        #expect(ReviewPromptHistory(isFirstLaunch: false).allowsRequest(version: "1.52", now: now))
    }

    @Test("Never twice for the same version")
    func sameVersion() {
        var history = ReviewPromptHistory(isFirstLaunch: false)
        history.recordRequest(version: "1.52", now: now - 200 * day)
        #expect(!history.allowsRequest(version: "1.52", now: now))
        #expect(history.allowsRequest(version: "1.53", now: now))
    }

    @Test("At most once every 120 days, whatever the version")
    func interval() {
        var history = ReviewPromptHistory(isFirstLaunch: false)
        history.recordRequest(version: "1.52", now: now)
        #expect(!history.allowsRequest(version: "1.53", now: now + 119 * day))
        #expect(history.allowsRequest(version: "1.53", now: now + 120 * day))
    }
}
