import Foundation

nonisolated public extension Double {
    /// `self` with `fractionDigits` decimals, no unit, in `locale`'s numerals —
    /// `1,5` in France, `1.5` in the US (issue #586). The whole app formats
    /// decimals this way, so the separator lives in one place.
    func decimalText(fractionDigits: Int = 1, locale: Locale = .app) -> String {
        formatted(.number.locale(locale).precision(.fractionLength(fractionDigits)))
    }
}

/// Millilitres rendered as litres with one decimal, no unit — e.g. `1,5`.
/// Callers append " L" where they want the unit.
nonisolated public func litres(_ millilitres: Int, locale: Locale = .app) -> String {
    (Double(millilitres) / 1_000).decimalText(locale: locale)
}

nonisolated public extension Int {
    /// `self` grouped by thousands the way `locale` groups them — `4 218` in
    /// France, `4,218` in the US (issue #586). `FormatStyle` keeps its
    /// formatters cached, which matters: this runs on every render of the step
    /// counters.
    func groupedText(locale: Locale = .app) -> String {
        formatted(.number.locale(locale))
    }
}
