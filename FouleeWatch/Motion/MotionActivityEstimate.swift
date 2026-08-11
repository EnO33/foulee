import Foundation

/// One `CMMotionActivity`, flattened into values.
///
/// This is the whole vocabulary the rest of the app has for "what is the wrist
/// doing" — nothing above `MotionActivitySource` imports CoreMotion, so every
/// consumer (the live detection of issue #249, the device probe of issue #248)
/// is exercisable on a simulator, where `CMMotionActivityManager` reports
/// itself unavailable and would otherwise deliver nothing at all.
///
/// Lived outside `FouleeWatch/Diagnostic/` on purpose, and outlived it: issue
/// #252 deleted the probe and its folder whole once the measurement was in,
/// and the detection had to stay.

/// One estimate, with both of its clocks.
///
/// `startDate` is the device's own stamp for when the activity began;
/// `receivedAt` is when this process was handed it. Both are kept, and they are
/// not the same question: a stale `startDate` with a fresh `receivedAt` is a
/// live stream reporting an activity that started a while ago, whereas a stale
/// `receivedAt` is a stream that has gone quiet. The detection uses the first
/// to date its segment boundaries and the second to reason about freshness.
///
/// Two of `CMMotionActivity`'s six booleans, and only two.
///
/// `stationary`, `unknown`, `cycling` and `automotive` were carried here while
/// the device probe of issue #248 displayed them; nothing reads them now, and a
/// field nobody reads is a field that can be wrong without anyone noticing.
/// Dropping them costs no guarantee: they are the flags Foulée does not record,
/// so an estimate carrying one of them leaves `walking` and `running` clear and
/// is no evidence either way — which is exactly what `reading(minimumConfidence:)`
/// already answers.
///
/// The two that remain are kept **separate**, not reduced to a verdict here:
/// they are not mutually exclusive and can both be false, so collapsing them is
/// a decision, and it belongs to `ActivitySwitchDetector` where it is stated
/// once and tested.
struct MotionActivityEstimate: Equatable, Sendable {
    var startDate: Date
    var receivedAt: Date
    var confidence: MotionActivityConfidence
    var walking: Bool
    var running: Bool
}
