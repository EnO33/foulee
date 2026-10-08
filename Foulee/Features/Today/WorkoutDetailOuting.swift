import Charts
import SwiftUI

/// The outing, sport by sport (issue #318): a timeline of its legs, then what
/// each sport added up to.
///
/// Shown only for an outing regrouped from several legs (#317). A single
/// session keeps the detail it always had — this block would only repeat the
/// hero.
struct WorkoutDetailOuting: View {
    let summary: WorkoutSummary

    /// Computed once, not on every `body` evaluation.
    private let shares: [SportShare]

    /// Where the finger is on the timeline (#319).
    @State private var selectedDate: Date?

    init(summary: WorkoutSummary) {
        self.summary = summary
        self.shares = OutingBreakdown.shares(of: summary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PORTIONS")
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            timeline
            selectionLine
            VStack(spacing: 10) {
                ForEach(shares) { share in
                    row(share)
                }
            }
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 22)
    }

    /// Every leg, end to end, its length the time it took. Swift Charts rather
    /// than hand-drawn bars, so the time axis — and its labels — come with it.
    private var timeline: some View {
        Chart(summary.legs) { leg in
            BarMark(
                xStart: .value("Début", leg.startedAt),
                xEnd: .value("Fin", leg.endedAt),
                y: .value("Sortie", "Sortie")
            )
            .foregroundStyle(leg.activity.tint)
            .cornerRadius(4)
            // The leg under the finger stays bright; the others step back.
            .opacity(selectedLeg.map { $0.id == leg.id ? 1 : 0.35 } ?? 1)
        }
        .chartXSelection(value: $selectedDate)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Frise de la sortie")
        .accessibilityValue(OutingBreakdown.timelineDescription(of: summary.legs))
    }

    private var selectedLeg: WorkoutSummary? {
        selectedDate.flatMap { OutingBreakdown.leg(at: $0, in: summary.legs) }
    }

    /// The leg under the finger, in words — or, until a finger lands, the
    /// hint that there is something to find. One line either way, so the
    /// block never jumps in height while scrubbing.
    private var selectionLine: some View {
        Group {
            if let leg = selectedLeg {
                HStack(spacing: 6) {
                    Image(systemName: leg.activity.icon)
                        .foregroundStyle(leg.activity.tint)
                    Text("\(leg.activity.label) · \(OutingBreakdown.legText(leg))")
                        .monospacedDigit()
                }
                .font(FouleeFont.footnote.weight(.semibold))
            } else {
                Text("Glisse le doigt sur la frise pour le détail d'une portion")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One sport: its glyph and name — so the colour is never the only cue —
    /// then the time, the distance and the pace it was done at.
    private func row(_ share: SportShare) -> some View {
        HStack(spacing: 12) {
            Image(systemName: share.activity.icon)
                .scaledSystemFont(size: 16, weight: .semibold)
                .foregroundStyle(share.activity.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(share.activity.label)
                    .font(FouleeFont.headline)
                Text(detailText(share))
                    .font(FouleeFont.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(share.duration.walkClockText)
                .scaledNumericFont(size: 18, weight: .semibold)
        }
        .accessibilityElement(children: .combine)
    }

    private func detailText(_ share: SportShare) -> String {
        [share.distanceKm.kmText(), share.paceText]
            .compactMap(\.self)
            .joined(separator: " · ")
    }
}
