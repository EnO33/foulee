import Foundation

extension Double {
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
func litres(_ millilitres: Int) -> String {
    (Double(millilitres) / 1_000).decimalComma()
}
