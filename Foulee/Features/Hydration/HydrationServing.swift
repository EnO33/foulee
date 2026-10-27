import Foundation

/// A quick amount to log (issue #355): the set glass, and three fixed sizes
/// around it. One tap still logs the set glass; these are a long press away
/// on the home, and laid out on the Hydratation screen.
nonisolated struct HydrationServing: Identifiable, Equatable, Sendable {
    var label: String
    var systemImage: String
    var milliliters: Int

    var id: String { label }

    /// Bottle size, unless the large glass already reaches it.
    static let bottleML = 500

    /// Small glass, the set glass, large glass, bottle — smallest first, each
    /// rounded to 10 mL so the buttons read cleanly.
    static func presets(glassML: Int) -> [HydrationServing] {
        let glass = max(glassML, 10)
        let large = rounded(Double(glass) * 1.6)
        return [
            HydrationServing(label: String(localized: "Petit verre"), systemImage: "drop", milliliters: rounded(Double(glass) * 0.6)),
            HydrationServing(label: String(localized: "Verre"), systemImage: "drop.fill", milliliters: glass),
            HydrationServing(label: String(localized: "Grand verre"), systemImage: "drop.halffull", milliliters: large),
            HydrationServing(
                label: String(localized: "Bouteille"),
                systemImage: "waterbottle.fill",
                milliliters: large < bottleML ? bottleML : rounded(Double(large) * 1.5)
            )
        ]
    }

    private static func rounded(_ milliliters: Double) -> Int {
        max(Int((milliliters / 10).rounded()) * 10, 10)
    }
}
