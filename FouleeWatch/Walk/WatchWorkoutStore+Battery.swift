import FouleeKit
import WatchKit

/// End the outing before the battery does (issue #614).
///
/// A watch that switches itself off finishes nothing: the builder never
/// becomes a workout, and the outing is gone from Santé. Low Power Mode needs
/// nothing from here — watchOS keeps the session running and only samples the
/// heart rate and the GPS less often.
///
/// Checked at every HealthKit batch, like the mirror: no timer of its own,
/// and nothing to decide while HealthKit says nothing.
extension WatchWorkoutStore {
    /// Stop and save through `stop()`, the one path that ends an outing, when
    /// the battery is about to give out. No-op once saving has begun.
    func endIfBatteryCritical() async {
        guard mirrorableMetrics != nil, battery().isCritical else { return }
        FouleeLog.session.notice("batterie critique, sortie arrêtée")
        endedOnLowBattery = true
        await stop()
    }
}

extension BatteryReading {
    /// The watch's own gauge. Monitoring is off until an app asks for it, and
    /// the level reads -1 until then.
    @MainActor static func watch() -> BatteryReading {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        return BatteryReading(
            level: device.batteryLevel,
            isCharging: device.batteryState == .charging || device.batteryState == .full
        )
    }
}
