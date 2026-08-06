import Foundation
import Testing
@testable import Foulee

/// Cover for what the Lock Screen says while a session runs (#225).
///
/// The views in `FouleeLiveActivity` cannot be exercised from a test process —
/// they are a `Widget`, rendered by WidgetKit out of process — so the title and
/// the glyph were pulled onto `WalkActivityAttributes`, which is a plain value
/// type. Asserting them here asserts what the four surfaces draw, because
/// after this change they all read those two members and hold no literal of
/// their own.
///
/// The decoding half is not hygiene. ActivityKit keeps an activity alive across
/// an app update, and both sweeps that can end a stranded one
/// (`FouleeApp.endOrphanedWalkActivitiesOnce`, `ActiveWalkStore.
/// startLiveActivity`) reach it only by enumerating
/// `Activity<WalkActivityAttributes>.activities` — an enumeration that has to
/// rebuild the attributes. Attributes that throw on last version's payload
/// would strand the activity on the Lock Screen with nothing able to end it.
/// What is *not* covered: that ActivityKit's own persistence goes through
/// `Codable` at all. That is the documented conformance requirement and the
/// only serialization contract the type exposes, but the archive format is
/// private and no test process can leave an activity in flight across a binary
/// swap. The tests below pin the contract this type owns.
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
