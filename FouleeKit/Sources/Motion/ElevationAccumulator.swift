import Foundation

/// The climb and the descent of an outing, in metres (issue #564). Measured
/// apart and never added: 100 m up and 100 m down is a 100 m climb.
nonisolated public struct Elevation: Equatable, Sendable {
    public var ascent: Double
    public var descent: Double

    public static let zero = Elevation(ascent: 0, descent: 0)

    public init(ascent: Double, descent: Double) {
        self.ascent = ascent
        self.descent = descent
    }

    public static func + (lhs: Elevation, rhs: Elevation) -> Elevation {
        Elevation(ascent: lhs.ascent + rhs.ascent, descent: lhs.descent + rhs.descent)
    }

    public static func += (lhs: inout Elevation, rhs: Elevation) {
        lhs = lhs + rhs
    }

    /// « ↑ 120 m · ↓ 115 m », either half left out under a metre, or `nil`
    /// when neither was measured (issue #535): absent, not « ↑ 0 m ».
    public var text: String? {
        let parts = [
            ascent >= 1 ? "↑ \(Int(ascent.rounded()).groupedText()) m" : nil,
            descent >= 1 ? "↓ \(Int(descent.rounded()).groupedText()) m" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The same, as VoiceOver says it: « 120 mètres de montée, 115 mètres de
    /// descente ».
    public var spokenText: String? {
        let parts = [
            ascent >= 1 ? kitText("\(Int(ascent.rounded())) mètres de montée") : nil,
            descent >= 1 ? kitText("\(Int(descent.rounded())) mètres de descente") : nil
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Turns a stream of (signed) relative-altitude readings into the climb and
/// the descent of an outing, the barometer's noise left out (issue #563).
/// Pure + value type so it's trivially unit-testable. In the kit since the
/// watch measures the climb too (issue #535).
///
/// **A threshold, not every delta.** The barometer reads about once a second
/// and never stands still: tenths of a metre up, tenths down, all the time.
/// Summing every rise counted each of those, and an hour on the flat came out
/// at hundreds of metres climbed. A change only counts once the altitude has
/// moved `threshold` away from the last point kept — the way sports watches
/// measure it — and then it counts whole, so a steady slope loses nothing but
/// its last few metres.
nonisolated public struct ElevationAccumulator: Sendable {
    /// How far the altitude must move from the last point kept before the
    /// move counts. Above the barometer's noise, below any slope a walker
    /// would call one.
    public static let threshold: Double = 3

    /// The last altitude a change was counted from.
    private var anchor: Double?
    public private(set) var elevation = Elevation.zero

    public init() {}

    /// Feed the next reading; returns the running climb and descent.
    public mutating func add(relativeAltitude: Double) -> Elevation {
        guard let anchor else {
            self.anchor = relativeAltitude
            return elevation
        }
        let delta = relativeAltitude - anchor
        guard abs(delta) >= Self.threshold else { return elevation }
        if delta > 0 {
            elevation.ascent += delta
        } else {
            elevation.descent -= delta
        }
        self.anchor = relativeAltitude
        return elevation
    }
}
