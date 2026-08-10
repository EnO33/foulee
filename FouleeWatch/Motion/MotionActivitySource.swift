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
    /// Opens the stream; `handler` is called once per estimate.
    ///
    /// There is deliberately no way to ask for the authorization *status*. The
    /// probe of issue #248 read it to put it on screen; nothing shipped acts on
    /// it, because there is nothing to do differently — opening the stream is
    /// what raises the prompt, and a refusal simply means no estimates arrive
    /// and the session stays the activity it was started as.
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
    /// The two flags are copied as they come, unreduced: they are not mutually
    /// exclusive and can both be false, so any attempt to pick a winner *here*
    /// would hide the ambiguity from the one place equipped to judge it.
    ///
    /// The other four — stationary, unknown, cycling, automotive — are not
    /// read. Foulée records neither a bike ride nor a car journey, so those
    /// flags could only ever produce « no evidence », which is what two clear
    /// booleans already produce.
    init(_ activity: CMMotionActivity, receivedAt: Date) {
        self.init(
            startDate: activity.startDate,
            receivedAt: receivedAt,
            confidence: MotionActivityConfidence(rawValue: activity.confidence.rawValue) ?? .unrecognised,
            walking: activity.walking,
            running: activity.running
        )
    }
}
