import Testing
@testable import Foulee

/// The one decision behind issue #224, in the one place both platforms read
/// it: does a tap on start record something, or ask first?
///
/// It replaces `SessionActivity.init(mode:)`, which had to return *an*
/// activity for every mode and therefore turned « les deux » into a walk. The
/// assertions below are what stops that from coming back — a `case .both:
/// self = .start(.walking)` would compile, ship, and quietly mislabel every
/// session such a user records, forever.
@Suite("Activity start intent")
struct ActivityStartIntentTests {
    @Test("A single-activity mode starts straight away — no question, one gesture")
    func singleActivityModesStartImmediately() {
        #expect(ActivityStartIntent(mode: .walking) == .start(.walking))
        #expect(ActivityStartIntent(mode: .running) == .start(.running))
        // The property the two screens branch on: non-nil means "start on
        // appear / on tap", so no picker is ever built for these two modes.
        #expect(ActivityStartIntent(mode: .walking).immediate == .walking)
        #expect(ActivityStartIntent(mode: .running).immediate == .running)
    }

    @Test("« Les deux » asks, and carries no activity to fall back on")
    func bothAsks() {
        #expect(ActivityStartIntent(mode: .both) == .ask)
        // Deliberately empty rather than "ask, defaulting to walking": a
        // default is exactly what a caller in a hurry would use, and it is how
        // a run ends up in Santé stamped as a walk. `HKWorkout` is immutable,
        // so that stamp is not fixable afterwards.
        #expect(ActivityStartIntent(mode: .both).immediate == nil)
    }

    @Test("Every mode is covered, and only « les deux » asks")
    func exactlyOneModeAsks() {
        // Over `allCases`, so a fourth mode added later cannot slip through
        // with an unconsidered intent. The count is spelled out because
        // mapping alone would be true by construction.
        let asking = ActivityMode.allCases.filter { ActivityStartIntent(mode: $0) == .ask }
        #expect(ActivityMode.allCases.count == 3)
        #expect(asking == [.both])
    }
}
