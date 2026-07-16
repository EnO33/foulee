import SwiftUI

/// Discreet freshness line ("MAJ 3 min") for the roomier families. The
/// `.relative` style is re-rendered by the system as time passes — the age
/// ticks with zero reloads. It emits a bare, growing duration (no "ago"), so
/// the prefix is "MAJ" rather than "il y a".
struct FreshnessStamp: View {
    let fetchedAt: Date

    var body: some View {
        Text("MAJ \(fetchedAt, style: .relative)")
            .font(.caption2)
            .lineLimit(1)
    }
}
