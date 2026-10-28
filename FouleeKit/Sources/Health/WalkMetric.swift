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
        case .steps: kitText("Pas")
        case .minutes: kitText("Minutes")
        case .distance: kitText("Distance")
        case .calories: kitText("Calories")
        }
    }

    /// Short unit shown after a value (`5 391 pas`, `4,2 km`, …).
    public var unit: String {
        switch self {
        case .steps: kitText("pas")
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

    /// The figure as VoiceOver says it (issue #600): « 4,2 kilomètres »,
    /// « 320 kilocalories », « 32 minutes ». The written units are spelled
    /// out letter by letter — « k m », « k cal ».
    public func spokenText(_ value: Double, locale: Locale = .app) -> String {
        switch self {
        case .steps:
            kitText("\(formatted(value, locale: locale)) pas", locale: locale)
        case .minutes:
            spokenDurationText(minutes: Int(value.rounded()), locale: locale)
        case .distance:
            Measurement(value: value, unit: UnitLength.kilometers).formatted(spoken(fractionDigits: 0...1, locale))
        case .calories:
            Measurement(value: value.rounded(), unit: UnitEnergy.kilocalories).formatted(spoken(fractionDigits: 0...0, locale))
        }
    }

    /// « 8 240 pas sur 10 000 pas », « 32 minutes sur 30 minutes »: the
    /// written « 8 240 / 10 000 pas » reads its slash aloud (issue #600).
    public func spokenText(_ value: Double, goal: Double, locale: Locale = .app) -> String {
        kitText("\(spokenText(value, locale: locale)) sur \(spokenText(goal, locale: locale))", locale: locale)
    }

    private func spoken<U: Dimension>(
        fractionDigits: ClosedRange<Int>,
        _ locale: Locale
    ) -> Measurement<U>.FormatStyle {
        .measurement(width: .wide, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(fractionDigits)))
            .locale(locale)
    }
}
