import Foundation
import Testing
@testable import FouleeKit

@Suite("WalkSession")
struct WalkSessionTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    @Test("Energy of a one-sport session: its steps at that sport's rate")
    func singleActivityCalories() {
        let walk = WalkSession(startedAt: start, steps: 1_000)
        #expect(walk.estimatedCalories == 40)
        let run = WalkSession(startedAt: start, steps: 1_000, activity: .running)
        #expect(run.estimatedCalories == 90)
    }

    @Test("Energy of a mixed session: each sport's steps at its own rate")
    func mixedActivityCalories() {
        let session = WalkSession(
            startedAt: start,
            steps: 1_000,
            stepsByActivity: [.walking: 500, .running: 500]
        )
        #expect(session.estimatedCalories == 65)
    }

    @Test("An empty split falls back to the session's own sport")
    func emptySplitFallsBack() {
        let session = WalkSession(startedAt: start, steps: 1_000, activity: .running, stepsByActivity: [:])
        #expect(session.estimatedCalories == 90)
    }

    @Test("Distance in kilometres")
    func distanceKm() {
        #expect(WalkSession(startedAt: start, distanceMeters: 2_500).distanceKm == 2.5)
    }
}
