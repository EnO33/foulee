import HealthKit
import SwiftUI
import Testing
@testable import FouleeWatch

/// Minimal stand-in for `WatchWorkoutHealthKit.live` — just enough to record
/// the configuration a start produces. `WatchWorkoutStoreTests` has the full
/// scriptable stub for the state machine; this one exists so the picker can be
/// followed all the way to what Santé would be handed.
@MainActor
private final class ConfigurationRecorder {
    private(set) var startedConfiguration: HKWorkoutConfiguration?

    func makeStore() -> WatchWorkoutStore {
        WatchWorkoutStore(healthKit: WatchWorkoutHealthKit(
            isAvailable: { true },
            requestAuthorization: { _, _ in },
            startSession: { configuration, _, _ in
                self.startedConfiguration = configuration
                let token = NSObject()
                return WatchWorkoutSessionHandle(
                    sessionID: ObjectIdentifier(token),
                    builderID: ObjectIdentifier(token),
                    startMirroring: {},
                    end: { _ = token },
                    endCollection: { _ in },
                    finishWorkout: {},
                    collectionEndDate: { nil }
                )
            }
        ), detection: WatchActivityDetection(source: .inert))
    }
}

/// The watch's picker (issue #224): whether the home screen's « Démarrer »
/// asks or starts, and what the answer records.
///
/// `WatchStartActivityTests` covers the mode → intent resolution and
/// `WatchWorkoutStoreTests` covers the configuration once an activity is
/// passed. The link between them is `WatchIdleScreen`, which is a `View` — so
/// it is walked with `ViewTreeProbe`, the real screen and its real closures,
/// rather than a stand-in that is not what ships.
@Suite("Watch activity picker")
@MainActor
struct WatchActivityPickerTests {
    /// What the screen's closures did — a reference type so the `struct`
    /// test's escaping closures can record into it.
    @MainActor
    final class Taps {
        var started: [SessionActivity] = []
        var asked = 0
        var cancelled = 0
    }

    /// The idle route as `WatchRootView` builds it, with the synced mode
    /// stubbed and every outcome recorded.
    private func idle(
        intent: ActivityStartIntent,
        isChoosingActivity: Bool = false,
        into taps: Taps
    ) -> WatchIdleScreen {
        WatchIdleScreen(
            today: WatchTodayStore(),
            isChoosingActivity: isChoosingActivity,
            intent: { intent },
            onStart: { taps.started.append($0) },
            onAsk: { taps.asked += 1 },
            onCancel: { taps.cancelled += 1 }
        )
    }

    @Test("« Les deux » makes the home button ask instead of starting")
    func bothAsksBeforeRecordingAnything() throws {
        let box = Taps()
        let screen = idle(intent: .ask, into: box)
        // The home screen's own CTA closure, pulled out of the tree it ships
        // in: this is the tap, not a re-implementation of it.
        let home = try #require(ViewTreeProbe.first(WatchTodayView.self, in: screen.body))
        home.onStart()

        #expect(box.asked == 1)
        // Nothing started. Before #224 this tap wrote a walk into Santé for
        // every « les deux » user, whatever they were actually doing.
        #expect(box.started.isEmpty)
    }

    @Test("A single-activity mode starts on the first tap, with no question")
    func singleActivityModesStartInOneGesture() throws {
        for (intent, expected) in [
            (ActivityStartIntent.start(.walking), SessionActivity.walking),
            (ActivityStartIntent.start(.running), SessionActivity.running)
        ] {
            let box = Taps()
            let screen = idle(intent: intent, into: box)
            try #require(ViewTreeProbe.first(WatchTodayView.self, in: screen.body)).onStart()

            #expect(box.started == [expected])
            // The whole point of keeping the picker out of these modes: the
            // user answered in Réglages, and one gesture is what they have.
            #expect(box.asked == 0)
        }
    }

    @Test("The home screen is untouched until the question is actually asked")
    func theQuestionIsNotOnTheHomeScreen() {
        let box = Taps()
        // Density criterion, held as a test: in « les deux » — the mode that
        // does ask — the home screen still builds exactly one CTA and no
        // picker. The question lives on its own screen, not as extra controls
        // squeezed under the streak hero and the 2×2 grid.
        let home = idle(intent: .ask, into: box).body
        #expect(ViewTreeProbe.contains(WatchTodayView.self, in: home))
        #expect(ViewTreeProbe.contains(WatchActivityChoiceView.self, in: home) == false)

        let asking = idle(intent: .ask, isChoosingActivity: true, into: box).body
        #expect(ViewTreeProbe.contains(WatchActivityChoiceView.self, in: asking))
        #expect(ViewTreeProbe.contains(WatchTodayView.self, in: asking) == false)
    }

    @Test("Choosing « Course » on the wrist stamps the session as a run")
    func choosingRunningStampsARun() async throws {
        let box = Taps()
        let screen = idle(intent: .ask, isChoosingActivity: true, into: box)
        let picker = try #require(ViewTreeProbe.first(WatchActivityChoiceView.self, in: screen.body))
        // The buttons live inside a `ForEach`, which keeps a closure instead
        // of its rows — building one is the only way to reach the real action.
        try #require(button(.running, picker)).select()
        #expect(box.started == [.running])

        // …and the end of the wire: the activity the button chose is what
        // HealthKit is configured with, which is verbatim what Santé keeps.
        let recorder = ConfigurationRecorder()
        let store = recorder.makeStore()
        await store.start(activity: try #require(box.started.first))
        #expect(recorder.startedConfiguration?.activityType == .running)
    }

    @Test("Choosing « Marche » stamps a walk, and the two buttons differ")
    func choosingWalkingStampsAWalk() async throws {
        let box = Taps()
        let screen = idle(intent: .ask, isChoosingActivity: true, into: box)
        let picker = try #require(ViewTreeProbe.first(WatchActivityChoiceView.self, in: screen.body))
        try #require(button(.walking, picker)).select()
        #expect(box.started == [.walking])

        let recorder = ConfigurationRecorder()
        let store = recorder.makeStore()
        await store.start(activity: try #require(box.started.first))
        // Asserted separately from the run so a picker whose two buttons both
        // chose the same activity fails here rather than looking correct.
        #expect(recorder.startedConfiguration?.activityType == .walking)
    }

    @Test("Both answers are offered, named the way Réglages names them")
    func theChoicesAreTheTwoActivities() throws {
        let box = Taps()
        let screen = idle(intent: .ask, isChoosingActivity: true, into: box)
        let picker = try #require(ViewTreeProbe.first(WatchActivityChoiceView.self, in: screen.body))

        #expect(try #require(button(.walking, picker)).activity.label == "Marche")
        #expect(try #require(button(.running, picker)).activity.label == "Course")
    }

    @Test("A mis-tap is recoverable: « Annuler » records nothing")
    func cancellingRecordsNothing() throws {
        let box = Taps()
        let screen = idle(intent: .ask, isChoosingActivity: true, into: box)
        let picker = try #require(ViewTreeProbe.first(WatchActivityChoiceView.self, in: screen.body))
        // The button the screen builds, not the closure it was handed. On the
        // watch this is the only way back — there is nothing behind this screen
        // to swipe to — so a dead « Annuler » is a user stuck staring at the
        // question with their home screen gone.
        try #require(ViewTreeProbe.first(WatchActivityCancelButton.self, in: picker.body)).cancel()

        #expect(box.cancelled == 1)
        #expect(box.started.isEmpty)
    }

    @Test("The way out is pinned to the screen, not scrolled away with the answers")
    func cancelIsOutsideTheScrolledRegion() throws {
        let box = Taps()
        let screen = idle(intent: .ask, isChoosingActivity: true, into: box)
        let picker = try #require(ViewTreeProbe.first(WatchActivityChoiceView.self, in: screen.body))
        let scrolled = try #require(scrolledRegion(of: picker.body))

        // The answers scroll: on a 40 mm screen two full-width buttons plus the
        // question already overflow at the larger Dynamic Type sizes, and the
        // crown is how the second one is reached.
        #expect(ViewTreeProbe.contains(
            ForEach<[SessionActivity], SessionActivity, WatchActivityChoiceButton>.self,
            in: scrolled
        ))
        // « Annuler » must not. It is the only way back — there is no
        // navigation bar behind this screen to swipe to — so scrolled with the
        // content it is off the bottom of a 40 mm screen at the default text
        // size and gone entirely at the larger ones, leaving a screen whose
        // only visible controls both start a permanent workout.
        #expect(ViewTreeProbe.contains(WatchActivityCancelButton.self, in: scrolled) == false)
        #expect(ViewTreeProbe.contains(WatchActivityCancelButton.self, in: picker.body))
    }

    /// The part of the picker the crown can push off the screen.
    ///
    /// Matched on the type's name because a `ScrollView`'s type spells out the
    /// whole of its content — naming it would mean rewriting the layout inside
    /// the test on every tweak, which is how a structural pin stops pinning
    /// anything.
    private func scrolledRegion(of value: Any, depth: Int = 24) -> Any? {
        if String(describing: type(of: value)).hasPrefix("ScrollView<") { return value }
        guard depth > 0 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let found = scrolledRegion(of: child.value, depth: depth - 1) { return found }
        }
        return nil
    }

    private func button(
        _ activity: SessionActivity,
        _ picker: WatchActivityChoiceView
    ) -> WatchActivityChoiceButton? {
        ViewTreeProbe.forEachRow(
            activity,
            of: ForEach<[SessionActivity], SessionActivity, WatchActivityChoiceButton>.self,
            in: picker.body
        )
    }
}
