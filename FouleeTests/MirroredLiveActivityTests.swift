import Foundation
import Testing
@testable import Foulee

/// What the Lock Screen draws for an outing running on the wrist (issue #275).
@Suite("Mirrored Live Activity")
struct MirroredLiveActivityTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func figures(at offset: TimeInterval, isPaused: Bool = false) -> WatchSessionSnapshot {
        WatchSessionSnapshot(
            sentAt: start.addingTimeInterval(offset),
            outingStartedAt: start,
            activity: .running,
            steps: 1_200,
            distanceMeters: 2_500,
            activeCalories: 140,
            heartRate: 150,
            isEnded: false,
            isPaused: isPaused
        )
    }

    @Test("Before the first figures, the clock runs from the outing's start on zeros")
    func noFiguresYet() {
        let state = MirroredLiveActivity.state(figures: nil, outingStartedAt: start)
        #expect(state.timerBasis == start)
        #expect(state.pausedAt == nil)
        #expect(state.steps == 0)
        #expect(state.distanceKm == 0)
    }

    @Test("The wrist's figures are drawn, and the clock runs from the outing's start")
    func runningFigures() {
        let state = MirroredLiveActivity.state(figures: figures(at: 600), outingStartedAt: start)
        #expect(state.timerBasis == start)
        #expect(state.pausedAt == nil)
        #expect(state.elapsed == 600)
        #expect(state.steps == 1_200)
        #expect(state.distanceKm == 2.5)
        #expect(state.activeCalories == 140)
    }

    /// The system clock stands still on `pausedAt`, which must be the instant
    /// the wrist stated the pause — not the phone's « now », which can be
    /// minutes later after a batched delivery.
    @Test("A paused outing freezes the clock where the wrist stopped it")
    func pausedFigures() {
        let state = MirroredLiveActivity.state(figures: figures(at: 900, isPaused: true), outingStartedAt: start)
        #expect(state.pausedAt == start.addingTimeInterval(900))
        #expect(state.elapsed == 900)
    }
}
