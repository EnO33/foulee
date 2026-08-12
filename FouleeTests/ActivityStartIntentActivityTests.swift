import Testing
@testable import Foulee

/// What « démarrer sur ma Watch » is allowed to send (issue #283).
///
/// `startWatchApp(toHandle:)` takes a concrete configuration, so there is
/// nothing to hand it in « les deux ». Picking one would stamp Santé with a
/// sport nobody chose, and that stamp is permanent (issue #223).
@Suite("Start intent's resolved activity")
struct ActivityStartIntentActivityTests {
    @Test("A decided mode names its sport", arguments: [SessionActivity.walking, .running])
    func aDecidedModeNamesIt(activity: SessionActivity) {
        #expect(ActivityStartIntent.start(activity).activity == activity)
    }

    /// The case the whole property exists for: no default, no fallback to a
    /// walk. The watch's own picker is where the question belongs (issue #224).
    @Test("« Les deux » names nothing, and must not be defaulted")
    func askNamesNothing() {
        #expect(ActivityStartIntent.ask.activity == nil)
    }
}
