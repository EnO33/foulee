import Foundation

/// A walk metric the user can drill into from the Today cards. Pure model
/// (no HealthKit, no SwiftUI) — the HK mapping lives in `HealthKitClient+Live`
/// and the icon/colour mapping in the stats views.
enum WalkMetric: String, CaseIterable, Identifiable, Sendable {
    case steps
    case minutes
    case distance
    case calories

    var id: String { rawValue }

    /// Title of the card and the stats screen.
    var title: String {
        switch self {
        case .steps: "Pas"
        case .minutes: "Minutes"
        case .distance: "Distance"
        case .calories: "Calories"
        }
    }

    /// Short unit shown after a value (`5 391 pas`, `4,2 km`, …).
    var unit: String {
        switch self {
        case .steps: "pas"
        case .minutes: "min"
        case .distance: "km"
        case .calories: "kcal"
        }
    }

    /// Distance is the only fractional metric.
    var fractionDigits: Int { self == .distance ? 1 : 0 }

    /// Format a value in this metric's display unit, without the unit suffix
    /// (`5 391`, `4,2`). Distance uses a French decimal comma; the rest use
    /// thousands grouping.
    func formatted(_ value: Double) -> String {
        if self == .distance { return value.kmValue(fractionDigits: 1) }
        return Int(value.rounded()).formattedFR
    }

    /// Same, with the unit appended (`5 391 pas`, `4,2 km`).
    func formattedWithUnit(_ value: Double) -> String {
        "\(formatted(value)) \(unit)"
    }
}
