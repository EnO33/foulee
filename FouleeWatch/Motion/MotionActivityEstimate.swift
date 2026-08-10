import Foundation

/// One `CMMotionActivity`, flattened into values.
///
/// This is the whole vocabulary the rest of the app has for "what is the wrist
/// doing" — nothing above `MotionActivitySource` imports CoreMotion, so every
/// consumer (the live detection of issue #249, the device probe of issue #248)
/// is exercisable on a simulator, where `CMMotionActivityManager` reports
/// itself unavailable and would otherwise deliver nothing at all.
///
/// Lives outside `Diagnostic/` on purpose: issue #252 deletes that folder
/// wholesale once the probe has done its job, and the detection must not go
/// with it.

/// How sure CoreMotion says it is. Mirrors `CMMotionActivityConfidence`; the
/// raw values are pinned against the real enum in the test suite.
///
/// `unrecognised` exists because a future watchOS could add a level, and
/// folding an unknown value into `low` would claim the device said something it
/// did not. It sorts *below* `low`, so any threshold rejects it — see
/// `ActivitySwitchDetector` for why that direction is the safe one.
enum MotionActivityConfidence: Int, CaseIterable, Comparable, Sendable {
    case unrecognised = -1
    case low = 0
    case medium = 1
    case high = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Mirrors `CMAuthorizationStatus`. Same reasoning as above for
/// `unrecognised`, and the raw values are pinned against CoreMotion's.
enum MotionAuthorization: Int, CaseIterable, Sendable {
    case unrecognised = -1
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case authorized = 3
}

/// One estimate, with both of its clocks.
///
/// `startDate` is the device's own stamp for when the activity began;
/// `receivedAt` is when this process was handed it. Both are kept, and they are
/// not the same question: a stale `startDate` with a fresh `receivedAt` is a
/// live stream reporting an activity that started a while ago, whereas a stale
/// `receivedAt` is a stream that has gone quiet. The detection uses the first
/// to date its segment boundaries and the second to reason about freshness.
///
/// The six booleans are kept separate rather than reduced to a verdict here.
/// They are **not mutually exclusive and can all be false**, so there is no
/// "primary" one to pick; collapsing them is a decision, and it belongs to
/// `ActivitySwitchDetector`, where it is stated once and tested.
struct MotionActivityEstimate: Equatable, Sendable {
    var startDate: Date
    var receivedAt: Date
    var confidence: MotionActivityConfidence
    var walking: Bool
    var running: Bool
    var stationary: Bool
    var unknown: Bool
    var cycling: Bool
    var automotive: Bool
}
