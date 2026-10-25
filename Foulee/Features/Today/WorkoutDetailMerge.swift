import FouleeKit
import SwiftUI

/// What the detail of an outing can merge it with, or undo (issue #552). Given
/// by the Bilan, which holds the outings around it and reads them again once
/// merged.
struct OutingMergeOptions {
    var previous: WorkoutSummary?
    var next: WorkoutSummary?
    var isMerged: Bool
    var merge: (WorkoutSummary) -> Void
    var separate: () -> Void

    /// Nothing to offer: no outing close enough, and no merge to undo.
    var isEmpty: Bool { previous == nil && next == nil && !isMerged }
}

/// « Fusionner avec la sortie de 10:42 » for each neighbour close enough, and
/// « Séparer les sorties » for an outing the wearer merged (issue #552).
struct WorkoutDetailMerge: View {
    let summary: WorkoutSummary
    let options: OutingMergeOptions

    /// The outing the wearer asked to merge with, until they confirm.
    @State private var proposed: WorkoutSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FUSION")
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            ForEach([options.previous, options.next].compactMap { $0 }) { other in
                action(Self.mergeTitle(with: other), icon: FouleeIcon.merge) { proposed = other }
            }
            if options.isMerged {
                action("Séparer les sorties", icon: FouleeIcon.separate, perform: options.separate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .fouleeGlass(cornerRadius: 22)
        .confirmationDialog(
            "Fusionner les deux sorties ?",
            isPresented: Binding(get: { proposed != nil }, set: { if !$0 { proposed = nil } }),
            titleVisibility: .visible,
            presenting: proposed
        ) { other in
            Button("Fusionner") { options.merge(other) }
            Button("Annuler", role: .cancel) {}
        } message: { other in
            Text(Self.confirmation(merging: summary, with: other))
        }
    }

    private func action(_ title: String, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: icon)
                .font(FouleeFont.callout.weight(.semibold))
                .foregroundStyle(FouleeColor.accentMid)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.pressable)
    }

    /// « Fusionner avec la sortie de 10:42 »: the hour the wearer remembers it
    /// by, whether it came before or after.
    static func mergeTitle(with other: WorkoutSummary) -> String {
        "Fusionner avec la sortie de \(other.startedAt.clockText)"
    }

    /// What the merge will give, then that it can be undone: « 08:00 → 09:12 ·
    /// 5,2 km au total. Santé n'est pas modifié : tu pourras les séparer à
    /// nouveau. »
    static func confirmation(merging outing: WorkoutSummary, with other: WorkoutSummary) -> String {
        let start = min(outing.startedAt, other.startedAt)
        let end = max(outing.endedAt, other.endedAt)
        let distance = (outing.distanceKm + other.distanceKm).kmText(fractionDigits: 1)
        return "\(start.clockText) → \(end.clockText) · \(distance) au total. "
            + "Santé n'est pas modifié : tu pourras les séparer à nouveau."
    }
}
