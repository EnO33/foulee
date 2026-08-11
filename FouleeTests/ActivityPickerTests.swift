import Clocks
import Dependencies
import SwiftUI
import Testing
@testable import Foulee

/// How the phone decides what a session was (issues #224, then #246).
///
/// It used to **ask**, on this very screen, because nothing could tell a walk
/// from a run and the stamp is permanent. The phone can tell now — from the
/// session's own CoreMotion history, read at `stop()` — so « les deux » starts
/// straight away like every other mode, names no sport while it runs, and is
/// settled from what the device measured before the workout is saved.
///
/// The tree is walked with `ViewTreeProbe` rather than testing a stand-in, so
/// what is asserted is the screen that ships, `@State` store and all.
@Suite("Activity decision (iPhone)")
@MainActor
struct ActivityPickerTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func screen(
        _ intent: ActivityStartIntent,
        store: ActiveWalkStore = ActiveWalkStore()
    ) -> ActiveWalkScreen {
        ActiveWalkScreen(minutesGoal: 20, intent: intent, store: store, onDismiss: { _ in })
    }

    private func session(of store: ActiveWalkStore) -> WalkSession? {
        guard case .active(let session) = store.state else { return nil }
        return session
    }

    /// Runs `body` with every sensor the store touches on `start` stubbed —
    /// the same set `ActiveWalkStoreTests` uses, so nothing here reaches a
    /// real pedometer, altimeter or Santé.
    private func withStubbedSensors(
        history: MotionActivityHistory = .testValue,
        _ body: () async throws -> Void
    ) async rethrows {
        try await withDependencies {
            $0.date = .constant(start)
            $0.pedometer = .testValue
            $0.healthKit = .testValue
            $0.motionActivityHistory = history
            $0.continuousClock = TestClock()
        } operation: {
            try await body()
        }
    }

    // MARK: - Nothing is asked any more

    @Test("« Les deux » starts straight away, like every other mode")
    func bothStartsWithoutAsking() async {
        let store = ActiveWalkStore()
        await withStubbedSensors {
            screen(.ask, store: store).startIfKnown()
        }
        // The question was a stopgap for a device that could not tell. It can.
        #expect(session(of: store) != nil)
        #expect(session(of: store)?.isActivityUndecided == true)
    }

    @Test("A mode that answers the question is not overruled")
    func aChosenModeStaysChosen() async {
        for activity in SessionActivity.allCases {
            let store = ActiveWalkStore()
            await withStubbedSensors {
                screen(.start(activity), store: store).startIfKnown()
            }
            #expect(session(of: store)?.activity == activity)
            // Not undecided: the user has said what they do, and detection is
            // not entitled to contradict an answer already given.
            #expect(session(of: store)?.isActivityUndecided == false)
        }
    }

    // MARK: - Nothing is named before it is known

    @Test("An unsettled session names no sport, on screen or on the Lock Screen")
    func anUndecidedSessionNamesNothing() async {
        let store = ActiveWalkStore()
        await withStubbedSensors {
            screen(.ask, store: store).startIfKnown()
        }
        // Naming « Ta marche » for a whole outing and saving « Course » at the
        // end would be the drift #225 was about, only worse.
        #expect(store.liveActivityAttributes(minutesGoal: 20).activity == nil)
        #expect(WalkActivityAttributes(goalMinutes: 20, activity: nil).title(isPaused: false) == "Ta sortie")
    }

    @Test("A settled session names its sport everywhere")
    func aDecidedSessionNamesItsSport() async {
        let store = ActiveWalkStore()
        await withStubbedSensors {
            screen(.start(.running), store: store).startIfKnown()
        }
        #expect(store.liveActivityAttributes(minutesGoal: 20).activity == .running)
    }

    // MARK: - What the device measured decides

    /// A history the test writes: `walking` for the first `runningAfter`
    /// seconds, running from there to the end.
    private func history(runningAfter: TimeInterval) -> MotionActivityHistory {
        MotionActivityHistory(
            samples: { from, _ in
                [
                    MotionHistorySample(startDate: from, confidence: .high, walking: true, running: false),
                    MotionHistorySample(
                        startDate: from.addingTimeInterval(runningAfter),
                        confidence: .high,
                        walking: false,
                        running: true
                    )
                ]
            }
        )
    }

    private func undecidedSession(endingAfter seconds: TimeInterval) -> WalkSession {
        var session = WalkSession(startedAt: start, activity: .walking, isActivityUndecided: true)
        session.endedAt = start.addingTimeInterval(seconds)
        return session
    }

    @Test("An outing mostly run is recorded as a run")
    func theDominantActivityWins() async {
        let store = ActiveWalkStore()
        var decided: WalkSession?
        await withStubbedSensors(history: history(runningAfter: 600)) {
            decided = await store.decidingActivity(of: undecidedSession(endingAfter: 1_800))
        }
        #expect(decided?.activity == .running)
        #expect(decided?.isActivityUndecided == false)
    }

    @Test("An outing mostly walked is recorded as a walk")
    func aMostlyWalkedOutingStaysAWalk() async {
        let store = ActiveWalkStore()
        var decided: WalkSession?
        await withStubbedSensors(history: history(runningAfter: 1_500)) {
            decided = await store.decidingActivity(of: undecidedSession(endingAfter: 1_800))
        }
        #expect(decided?.activity == .walking)
    }

    @Test("A session the user chose the sport of is handed back untouched")
    func aChosenSessionIsNeverOverridden() async {
        let store = ActiveWalkStore()
        var chosen = WalkSession(startedAt: start, activity: .walking)
        chosen.endedAt = start.addingTimeInterval(1_800)
        var decided: WalkSession?
        // A history that screams « course » from end to end.
        await withStubbedSensors(history: history(runningAfter: 0)) {
            decided = await store.decidingActivity(of: chosen)
        }
        // « Marche » in Réglages is an answer already given. Overriding it
        // would also over-credit: kcalPerStep is 0.09 running against 0.04.
        #expect(decided?.activity == .walking)
    }

    @Test("A device that says nothing leaves the session a walk")
    func asilentDeviceUnderCredits() async {
        let store = ActiveWalkStore()
        var decided: WalkSession?
        // `testValue` reports itself unavailable and returns no samples — a
        // simulator, or a phone whose motion permission was refused.
        await withStubbedSensors {
            decided = await store.decidingActivity(of: undecidedSession(endingAfter: 1_800))
        }
        #expect(decided?.activity == .walking)
        #expect(decided?.isActivityUndecided == false)
    }
}
