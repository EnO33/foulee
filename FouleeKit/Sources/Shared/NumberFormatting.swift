import Foundation

nonisolated public extension Double {
    /// `self` with `fractionDigits` decimals and a French decimal comma, no
    /// unit — e.g. `1,5`. The whole app formats decimals this way, so the
    /// comma lives in one place.
    func decimalComma(fractionDigits: Int = 1) -> String {
        String(format: "%.\(fractionDigits)f", self)
            .replacingOccurrences(of: ".", with: ",")
    }
}

/// Millilitres rendered as litres with one decimal + comma, no unit — e.g.
/// `1,5`. Callers append " L" where they want the unit.
nonisolated public func litres(_ millilitres: Int) -> String {
    (Double(millilitres) / 1_000).decimalComma()
}

nonisolated private let frenchDecimalFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "fr_FR")
    formatter.numberStyle = .decimal
    return formatter
}()

nonisolated public extension Int {
    /// French-locale thousands grouping (`4218` → `"4 218"`). Uses a shared
    /// cached formatter — allocating a `NumberFormatter` per call is costly and
    /// this runs on every render of the step counters.
    var formattedFR: String {
        frenchDecimalFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
