import SwiftUI
import Testing
@testable import Foulee

/// The phone's picker, on the screen that ships it (issue #224).
///
/// `ActivityStartIntentTests` covers the decision and `TodayStoreActivityTests`
/// covers the store that makes it; these cover the step in between, which is a
/// `View` body and therefore the step nothing else can see: whether the
/// session screen actually *shows* the question in « les deux » — and, just as
/// importantly, whether it stays out of the way in the other two modes, where
/// an extra tap would be a regression.
///
/// The tree is walked with `ViewTreeProbe` rather than testing a stand-in, so
/// what is asserted is the screen that ships, `@State` store and all.
@Suite("Activity picker (iPhone)")
@MainActor
struct ActivityPickerTests {
    private func screen(_ intent: ActivityStartIntent, onCancel: @escaping () -> Void = {}) -> ActiveWalkScreen {
        ActiveWalkScreen(minutesGoal: 20, intent: intent, onDismiss: { _ in }, onCancel: onCancel)
    }

    @Test("« Les deux » opens the session screen on the question")
    func bothShowsThePicker() {
        // The store is idle at build time — the state the screen is in the
        // instant the fullScreenCover appears, before anything is recorded.
        #expect(ViewTreeProbe.contains(ActivityChoiceScreen.self, in: screen(.ask).body))
    }

    @Test("A single-activity mode shows no picker at all")
    func singleActivityModesShowNoPicker() {
        // The acceptance criterion that is easiest to break by accident:
        // showing the question to everyone "for consistency" costs a tap on
        // every single session for users who already answered it in Réglages.
        #expect(ViewTreeProbe.contains(ActivityChoiceScreen.self, in: screen(.start(.walking)).body) == false)
        #expect(ViewTreeProbe.contains(ActivityChoiceScreen.self, in: screen(.start(.running)).body) == false)
    }

    @Test("The question offers exactly walking and running, named as everywhere else")
    func theChoicesAreTheTwoActivities() throws {
        let picker = try #require(ViewTreeProbe.first(ActivityChoiceScreen.self, in: screen(.ask).body))
        let walk = try #require(button(.walking, picker))
        let run = try #require(button(.running, picker))

        #expect(walk.activity.label == "Marche")
        #expect(run.activity.label == "Course")
        // Two answers, no third: `SessionActivity` has exactly the cases that
        // can reach Santé, and the picker offers all of them.
        #expect(SessionActivity.allCases == [.walking, .running])
    }

    @Test("Tapping « Course » starts a run, tapping « Marche » a walk")
    func eachButtonChoosesItsOwnActivity() throws {
        // The buttons live inside a `ForEach`, which stores a closure instead
        // of its rows: building one through the probe is the only way to reach
        // the real tap action, and a picker whose two buttons both chose
        // walking would otherwise look perfectly fine.
        var chosen: [SessionActivity] = []
        let picker = ActivityChoiceScreen(onChoose: { chosen.append($0) }, onCancel: {})
        button(.running, picker)?.select()
        button(.walking, picker)?.select()

        #expect(chosen == [.running, .walking])
    }

    @Test("Backing out records nothing")
    func cancelDismissesWithoutASession() throws {
        // Distinct from `onDismiss`, which carries a finished session the home
        // overlays onto today's counters. A cancel routed there would credit a
        // session that never happened.
        var cancelled = false
        var dismissed = false
        let live = ActiveWalkScreen(
            minutesGoal: 20,
            intent: .ask,
            onDismiss: { _ in dismissed = true },
            onCancel: { cancelled = true }
        )
        let picker = try #require(ViewTreeProbe.first(ActivityChoiceScreen.self, in: live.body))
        // The button the screen builds, not the closure it was handed: reading
        // back `picker.onCancel` would pass just as happily with a « Annuler »
        // wired to nothing, which strands the user on the picker.
        try #require(ViewTreeProbe.first(ActivityChoiceCancelButton.self, in: picker.body)).cancel()

        #expect(cancelled)
        #expect(dismissed == false)
    }

    /// The button the picker builds for one activity, rebuilt from the live
    /// screen on every call.
    private func button(_ activity: SessionActivity, _ picker: ActivityChoiceScreen) -> ActivityChoiceButton? {
        ViewTreeProbe.forEachRow(
            activity,
            of: ForEach<[SessionActivity], SessionActivity, ActivityChoiceButton>.self,
            in: picker.body
        )
    }
}
