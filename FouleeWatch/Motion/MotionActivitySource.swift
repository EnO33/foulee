import CoreMotion
import Foundation

/// The app's only contact with CoreMotion, as four closures.
///
/// Hand-written, because the watch target links no dependency container — the
/// same shape of seam as `WatchWorkoutHealthKit`. It earns its place for one
/// reason: `CMMotionActivityManager.isActivityAvailable()` is `false` on every
/// simulator (verified on watchOS 26.5, where `authorizationStatus()` is
/// `notDetermined` too), so through the real CoreMotion everything downstream —
/// the retry that opens the stream the moment the device says it can, and the
/// segment switching of issue #249 — would be reachable only on a wrist.
struct MotionActivitySource: Sendable {
    var isAvailable: @MainActor () -> Bool
    var authorization: @MainActor () -> MotionAuthorization
    /// Opens the stream; `handler` is called once per estimate.
    var openStream: @MainActor (_ handler: @escaping @Sendable (MotionActivityEstimate) -> Void) -> Void
    var closeStream: @MainActor () -> Void

    /// The real one. A single `CMMotionActivityManager`, captured by the two
    /// closures that need it: allocating it prompts nothing and starts nothing
    /// — the stream, and with it the permission sheet, only opens in
    /// `openStream`.
    @MainActor
    static func live() -> MotionActivitySource {
        let manager = CMMotionActivityManager()
        return MotionActivitySource(
            isAvailable: { CMMotionActivityManager.isActivityAvailable() },
            authorization: {
                MotionAuthorization(
                    rawValue: CMMotionActivityManager.authorizationStatus().rawValue
                ) ?? .unrecognised
            },
            openStream: { handler in
                // Delivered on the main queue, and converted to a value
                // immediately: `CMMotionActivity` is a reference type this app
                // must not hold on to.
                manager.startActivityUpdates(to: .main) { activity in
                    guard let activity else { return }
                    handler(MotionActivityEstimate(activity, receivedAt: .now))
                }
            },
            closeStream: { manager.stopActivityUpdates() }
        )
    }
}

extension MotionActivityEstimate {
    /// The CoreMotion boundary, in full.
    ///
    /// Each flag copied on its own line: `CMMotionActivity`'s booleans are not
    /// mutually exclusive and can all be false at once, so any attempt to
    /// reduce them *here* would throw away information the caller may need.
    init(_ activity: CMMotionActivity, receivedAt: Date) {
        self.init(
            startDate: activity.startDate,
            receivedAt: receivedAt,
            confidence: MotionActivityConfidence(rawValue: activity.confidence.rawValue) ?? .unrecognised,
            walking: activity.walking,
            running: activity.running,
            stationary: activity.stationary,
            unknown: activity.unknown,
            cycling: activity.cycling,
            automotive: activity.automotive
        )
    }
}
