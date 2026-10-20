import Foundation

/// Tolerant readers for the fields of a Connect IQ message, shared by every
/// decoder of the watch's messages (ADR 0009, D6).
///
/// The message crosses a BLE link from a device the app doesn't control, so
/// none of these traps or throws: a value they can't make sense of is nil, and
/// each decoder decides whether that rejects the message or defaults the field.
nonisolated enum ConnectIQField {
    /// `NSNumber`-only on purpose: a numeric-looking `NSString` is a watch-side
    /// bug, and silently coercing it would hide it.
    static func finiteDouble(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    static func integer(_ value: Any?) -> Int? {
        guard let double = finiteDouble(value) else { return nil }
        // Saturate instead of trapping: `Int(_: Double)` crashes out of range,
        // and a corrupt payload must never take the app down.
        if double >= Double(Int.max) { return Int.max }
        if double <= Double(Int.min) { return Int.min }
        return Int(double.rounded())
    }

    static func positiveDate(_ value: Any?) -> Date? {
        guard let seconds = finiteDouble(value), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// A counter: missing or non-numeric is 0, negative is clamped to 0.
    static func nonNegative(_ value: Any?) -> Int {
        max(0, integer(value) ?? 0)
    }
}
