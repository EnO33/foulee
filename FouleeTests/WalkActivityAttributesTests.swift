import Foundation
import Testing
@testable import Foulee

/// Cover for the value the Lock Screen reads while a session runs (#225).
///
/// Scope, stated precisely — this suite covers `WalkActivityAttributes` and
/// nothing else:
/// * **covered here** — what a given attributes value says: its title, its
///   glyph, and its decoding of a payload written by another build.
/// * **covered next door** — that `ActiveWalkStore` builds that value off the
///   session's own activity rather than a constant
///   (`ActiveWalkStoreTests.liveActivityCarriesTheStartedActivity`). Without
///   that test, the wiring could go back to a hardcoded `.walking` with every
///   expectation below still green.
/// * **not covered** — the four reads in `FouleeLiveActivity.WalkLiveActivity`
///   (Lock Screen row, Dynamic Island expanded/compact/minimal). They live in a
///   `Widget`, which WidgetKit renders out of process, and no test target can
///   instantiate one. The title and the glyph were pulled onto this value type
///   so that the *derivation* is testable; that the views read it back is held
///   by review only.
/// * **not covered** — that ActivityKit persists attributes through `Codable`
///   at all, or that `Activity.activities` surfaces an activity whose
///   attributes type changed shape between builds. The archive format is
///   private and no test process can leave an activity in flight across a
///   binary swap. The decoding tests below therefore prove Foundation-level
///   tolerance, not the app-update scenario that motivates it — see
///   `WalkActivityAttributes.init(from:)`, which says the same in the code.
@Suite("Live Activity attributes")
struct WalkActivityAttributesTests {
    @Test("A run announces itself as a run")
    func runReadsAsRun() {
        let attributes = WalkActivityAttributes(goalMinutes: 20, activity: .running)

        #expect(attributes.title(isPaused: false) == "Ta course")
        #expect(attributes.title(isPaused: true) == "Ta course · En pause")
        // The literal, not `ActivityGlyph.run`: comparing against the same
        // constant the implementation reads would hold for any symbol name,
        // including the walking figure this issue exists to stop showing.
        #expect(attributes.glyph == "figure.run")
    }

    @Test("A walk announces itself as a walk")
    func walkReadsAsWalk() {
        let attributes = WalkActivityAttributes(goalMinutes: 20, activity: .walking)

        #expect(attributes.title(isPaused: false) == "Ta marche")
        #expect(attributes.title(isPaused: true) == "Ta marche · En pause")
        #expect(attributes.glyph == "figure.walk")
    }

    @Test("An activity the payload never named stays neutral, as #222 left it")
    func unnamedActivityStaysNeutral() {
        let attributes = WalkActivityAttributes(goalMinutes: 20, activity: nil)

        // Deliberately not « Ta marche »: this is the payload of a session
        // started before the app recorded what it was, so it may well be a
        // run. Naming it walking would put back the exact wrong label #225
        // removes, on the one payload that cannot be checked.
        #expect(attributes.title(isPaused: false) == "Ta sortie")
        #expect(attributes.title(isPaused: true) == "Ta sortie · En pause")
        #expect(attributes.glyph == "figure.mixed.cardio")
    }

    @Test("Two activities, two distinct titles and two distinct glyphs")
    func theTwoActivitiesNeverCollide() {
        let walk = WalkActivityAttributes(goalMinutes: 20, activity: .walking)
        let run = WalkActivityAttributes(goalMinutes: 20, activity: .running)
        let unknown = WalkActivityAttributes(goalMinutes: 20, activity: nil)

        #expect(Set([walk.glyph, run.glyph, unknown.glyph]).count == 3)
        #expect(
            Set([
                walk.title(isPaused: false),
                run.title(isPaused: false),
                unknown.title(isPaused: false)
            ]).count == 3
        )
    }

    @Test("A payload written without the field still decodes, as the unnamed case")
    func legacyPayloadDecodes() throws {
        // Byte-for-byte what a build before #225 encoded: one key.
        let legacy = Data(#"{"goalMinutes":30}"#.utf8)

        let decoded = try JSONDecoder().decode(WalkActivityAttributes.self, from: legacy)

        #expect(decoded.goalMinutes == 30)
        #expect(decoded.activity == nil)
        #expect(decoded.title(isPaused: false) == "Ta sortie")
        #expect(decoded.glyph == "figure.mixed.cardio")
    }

    @Test("A payload naming an activity this build has no case for decodes too")
    func unrecognisedActivityDecodes() throws {
        // The reverse direction of the same problem: an older binary handed a
        // newer payload (an install rolled back through TestFlight, or a third
        // activity added later). Swift's synthesized decoder throws
        // `dataCorrupted` here — this is the case the hand-written
        // `init(from:)` exists for.
        let future = Data(#"{"goalMinutes":30,"activity":"cycling"}"#.utf8)

        let decoded = try JSONDecoder().decode(WalkActivityAttributes.self, from: future)

        #expect(decoded.goalMinutes == 30)
        #expect(decoded.activity == nil)
        #expect(decoded.glyph == "figure.mixed.cardio")
    }

    @Test("A payload whose activity is not even a string decodes too")
    func mistypedActivityDecodes() throws {
        // Third shape of the same problem, and the one a corrupted or
        // re-encoded archive would produce. `try?` covers it like the other
        // two rather than only the cases that were anticipated.
        let mistyped = Data(#"{"goalMinutes":30,"activity":42}"#.utf8)

        let decoded = try JSONDecoder().decode(WalkActivityAttributes.self, from: mistyped)

        #expect(decoded.goalMinutes == 30)
        #expect(decoded.activity == nil)
        #expect(decoded.title(isPaused: false) == "Ta sortie")
    }

    @Test("The tolerance holds under the property-list coder, not just JSON")
    func toleranceHoldsUnderPropertyListCoder() throws {
        // Which Foundation coder ActivityKit hands these attributes to is not
        // documented — the archive format is private. So the tolerance is
        // checked under both coders rather than assumed of the one the tests
        // above happen to use.
        struct LegacyPayload: Encodable { let goalMinutes: Int }
        struct FuturePayload: Encodable { let goalMinutes: Int, activity: String }

        let legacy = try PropertyListEncoder().encode(LegacyPayload(goalMinutes: 30))
        let future = try PropertyListEncoder().encode(
            FuturePayload(goalMinutes: 30, activity: "cycling")
        )

        for payload in [legacy, future] {
            let decoded = try PropertyListDecoder().decode(WalkActivityAttributes.self, from: payload)

            #expect(decoded.goalMinutes == 30)
            #expect(decoded.activity == nil)
            #expect(decoded.glyph == "figure.mixed.cardio")
        }

        // And a payload this build wrote survives the same round trip, so the
        // tolerance is not bought by losing the field under that coder.
        let current = try PropertyListEncoder().encode(
            WalkActivityAttributes(goalMinutes: 45, activity: .running)
        )
        let restored = try PropertyListDecoder().decode(WalkActivityAttributes.self, from: current)

        #expect(restored.activity == .running)
        #expect(restored.title(isPaused: false) == "Ta course")
    }

    @Test("A payload that does name an activity round-trips")
    func roundTripKeepsTheActivity() throws {
        for activity in SessionActivity.allCases {
            let encoded = try JSONEncoder().encode(
                WalkActivityAttributes(goalMinutes: 45, activity: activity)
            )
            let decoded = try JSONDecoder().decode(WalkActivityAttributes.self, from: encoded)

            #expect(decoded.activity == activity)
            #expect(decoded.goalMinutes == 45)
        }
    }

    @Test("Tolerance stops at the activity: a payload missing the goal still throws")
    func goalMinutesStaysRequired() {
        // `goalMinutes` has been in every payload ever written, so its absence
        // means corruption rather than age. Swallowing it would hide a real
        // bug behind a Lock Screen ring stuck at 0 %.
        let corrupt = Data(#"{"activity":"running"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WalkActivityAttributes.self, from: corrupt)
        }
    }
}
