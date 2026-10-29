import Foundation

/// The watch's charge, as the outing in flight sees it (issue #614).
///
/// An outing the battery cuts short is lost: the builder only becomes a
/// workout in Santé when it is finished, and a watch that switches itself off
/// finishes nothing. So the outing ends itself first, while there is still
/// charge to save it.
nonisolated public struct BatteryReading: Equatable, Sendable {
    /// Saving takes seconds; 5 % leaves room for them, and for the summary.
    public static let criticalLevel: Float = 0.05

    /// 0…1, negative when the system cannot tell (monitoring off, simulator).
    public var level: Float
    /// On the charger: the battery is not running out, whatever it reads.
    public var isCharging: Bool

    public init(level: Float, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
    }

    /// Low enough that the outing must end now. An unknown level never is:
    /// ending a healthy outing on a misread costs more than the risk.
    public var isCritical: Bool {
        !isCharging && level >= 0 && level <= Self.criticalLevel
    }
}
