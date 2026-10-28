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

extension View {
    /// The widget's figures as one VoiceOver element (issue #601): « Pas,
    /// 8 240 pas sur 10 000 pas, mis à jour il y a 3 min » rather than the
    /// glyph, « 8 240 barre oblique 10 000 » and « MAJ » one by one. A button
    /// inside the widget stays out of it: apply this to the figures only.
    /// Without a `value`, the label says it all — « Série de 12 jours ».
    @ViewBuilder
    func widgetSummary(_ label: Text, value: String? = nil, fetchedAt: Date? = nil) -> some View {
        let element = accessibilityElement(children: .ignore).accessibilityLabel(label)
        if let value {
            element.accessibilityValue(
                fetchedAt.map { Text("\(value), mis à jour il y a \($0, style: .relative)") } ?? Text(value)
            )
        } else {
            element
        }
    }
}
