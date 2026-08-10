import Foundation
import HealthKit
import Testing
@testable import Foulee

/// Naming a session already in Santé (issue #245).
///
/// The reason this matters is asymmetric with how small it looks. `HKWorkout`
/// is immutable and Foulée has no delete path, so a session stamped with the
/// wrong sport — by the picker, or by the watch's automatic detection since
/// #249 — is wrong for good. Until this issue nothing in the app displayed the
/// type at all, so the mistake was also invisible. These rows are what makes it
/// noticeable, which is the only thing that makes it correctable by hand.
@Suite("Recorded activity")
struct RecordedActivityTests {
    // MARK: - Reading the type back

    @Test("The three types the résumé lists are named, never lumped together")
    func theListedTypesAreNamed() {
        #expect(RecordedActivity(.walking) == .walking)
        #expect(RecordedActivity(.running) == .running)
        #expect(RecordedActivity(.hiking) == .hiking)
    }

    /// The load-bearing one: it ties #217's filter to #245's labels.
    @Test("Every type the filter accepts has a name of its own")
    func theFilterAndTheLabelsCannotDrift() {
        for type in WorkoutActivityFilter.summarizedActivityTypes {
            // Widening the filter without naming the new type would put rows in
            // the résumé that all read « Séance » — the neutral label is for
            // what cannot be named, not a place to quietly park new types.
            #expect(
                RecordedActivity(type) != .other,
                "\(type.rawValue) passe le filtre du résumé mais n'a pas de nom"
            )
        }
    }

    @Test("A type Foulée does not record still appears, named neutrally")
    func anUnknownTypeIsNotHidden() {
        // It happened, and hiding it would be a worse lie than « Séance ». The
        // *write* side refuses these outright — that one feeds a permanent
        // stamp, this one feeds a label.
        #expect(RecordedActivity(.cycling) == .other)
        #expect(RecordedActivity(.swimming) == .other)
        #expect(SessionActivity(.cycling) == nil)
    }

    // MARK: - How it reads

    @Test("Each activity reads distinctly, in the app's established vocabulary")
    func labelsAndGlyphsAreDistinct() {
        // « Marche » and « Course » are the words the pickers use since #222 —
        // a user who chose « Course » in Réglages must read the same word here.
        #expect(RecordedActivity.walking.label == "Marche")
        #expect(RecordedActivity.running.label == "Course")
        #expect(RecordedActivity.hiking.label == "Randonnée")
        #expect(RecordedActivity.other.label == "Séance")

        // Four rows drawing one figure is the state this issue found the app
        // in; four labels sharing a word would be the same failure in prose.
        #expect(Set(RecordedActivity.allCases.map(\.label)).count == RecordedActivity.allCases.count)
        #expect(Set(RecordedActivity.allCases.map(\.icon)).count == RecordedActivity.allCases.count)
    }

    @Test("The unnamed case keeps the neutral figure the screens used before")
    func theNeutralGlyphIsTheOldOne() {
        #expect(RecordedActivity.other.icon == ActivityGlyph.mixedCardio)
        #expect(RecordedActivity.walking.icon == ActivityGlyph.walk)
        #expect(RecordedActivity.running.icon == ActivityGlyph.run)
    }

    // MARK: - What a summary built without an answer says

    @Test("A summary built without a type claims nothing rather than a walk")
    func theDefaultDoesNotInventAWalk() {
        let summary = WorkoutSummary(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_001_800),
            durationSeconds: 1_800,
            distanceKm: 2.4,
            activeCalories: 120,
            sourceName: "Foulée"
        )
        // Defaulting to `.walking` is the shape of issue #223, which stamped
        // every session the app ever wrote as a walk — run or not. A call site
        // that forgets must show « Séance », not assert something.
        #expect(summary.activity == .other)
    }
}
