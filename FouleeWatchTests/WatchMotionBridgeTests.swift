import CoreMotion
import Foundation
import Testing
@testable import FouleeWatch

/// The one-line bridge out of `CMMotionActivity`, pinned against CoreMotion's
/// own constants.
///
/// Rescued from the device probe's suite when issue #252 removed it. The probe
/// went; what it was pinning did not. `MotionActivityConfidence` maps **by raw
/// value**, and the detection of issue #249 refuses every reading below
/// `.medium` — so a drift in those numbers would not crash, would not fail to
/// compile, and would not show on screen. It would quietly re-grade every
/// estimate taken on a wrist: confident readings dismissed as weak, or weak
/// ones acted on and written into Santé as a segment.
@Suite("Watch motion bridge")
struct WatchMotionBridgeTests {
    @Test("Confidence mirrors CoreMotion's own constants")
    func confidenceRawValuesMatchCoreMotion() {
        #expect(MotionActivityConfidence.low.rawValue == CMMotionActivityConfidence.low.rawValue)
        #expect(MotionActivityConfidence.medium.rawValue == CMMotionActivityConfidence.medium.rawValue)
        #expect(MotionActivityConfidence.high.rawValue == CMMotionActivityConfidence.high.rawValue)
    }

    @Test("A level CoreMotion could add one day is not read as a level we know")
    func anUnknownLevelIsNotSilentlyPromoted() {
        // `unrecognised` is what the bridge falls back to, and it must sort
        // *below* every real level: an unnameable confidence is not evidence,
        // and the alternative — folding it into one of the three — would act on
        // a grade the device never gave.
        #expect(MotionActivityConfidence(rawValue: 99) == nil)
        for known in MotionActivityConfidence.allCases where known != .unrecognised {
            #expect(MotionActivityConfidence.unrecognised < known)
        }
    }
}
