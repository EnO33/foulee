import Foundation

/// A walk metric the user can drill into from the Today cards. Pure model
/// (no HealthKit, no SwiftUI) — the HK mapping lives in `HealthKitClient+Live`
/// and the icon/colour mapping in the stats views.
nonisolated public enum WalkMetric: String, CaseIterable, Identifiable, Sendable {
    case steps
    case minutes
    case distance
    case calories

    public var id: String { rawValue }

    /// Title of the card and the stats screen.
    public var title: String {
        switch self {
        case .steps: "Pas"
        case .minutes: "Minutes"
        case .distance: "Distance"
        case .calories: "Calories"
        }
    }

    /// Short unit shown after a value (`5 391 pas`, `4,2 km`, …).
    public var unit: String {
        switch self {
        case .steps: "pas"
        case .minutes: "min"
        case .distance: "km"
        case .calories: "kcal"
        }
    }

    /// Distance is the only fractional metric.
    public var fractionDigits: Int { self == .distance ? 1 : 0 }

    /// Format a value in this metric's display unit, without the unit suffix
    /// (`5 391`, `4,2`), in `locale`'s numerals. Fractional metrics keep their
    /// own precision; whole-number metrics use thousands grouping. The branch
    /// follows `fractionDigits`, so a new fractional metric needs no change here.
    public func formatted(_ value: Double, locale: Locale = .app) -> String {
        guard fractionDigits > 0 else { return Int(value.rounded()).groupedText(locale: locale) }
        return value.decimalText(fractionDigits: fractionDigits, locale: locale)
    }

    /// A chart axis graduation (issue #370): the bare figure, but minutes as a
    /// duration — `2 h` rather than `120`.
    public func axisText(_ value: Double) -> String {
        self == .minutes ? durationText(minutes: Int(value.rounded())) : formatted(value)
    }

    /// Same, with the unit appended (`5 391 pas`, `4,2 km`) — and minutes as
    /// a duration, `1 h 05` rather than `65 min` (issue #366).
    public func formattedWithUnit(_ value: Double) -> String {
        guard self != .minutes else { return durationText(minutes: Int(value.rounded())) }
        return "\(formatted(value)) \(unit)"
    }
}
