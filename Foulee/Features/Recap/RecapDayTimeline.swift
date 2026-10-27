import Dependencies
import FouleeKit
import SwiftUI

/// The day picked in the Bilan (issues #348, #350, #361): how it went against
/// the goal, then its outings on a timeline, newest on top, each at its hour,
/// in its sport's colour, opening its detail.
struct RecapDayTimeline: View {
    let outings: OutingDay
    let ring: Recap.Day
    let goalMinutes: Int

    @Dependency(\.date) private var date

    /// Newest first, as `OutingDay` files them (issue #361).
    private var workouts: [WorkoutSummary] { outings.workouts }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if workouts.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: emptyIcon)
                        .scaledSystemFont(size: 18)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(emptyTitle)
                            .font(FouleeFont.footnote)
                            .foregroundStyle(.secondary)
                        if let emptyHint {
                            Text(emptyHint)
                                .font(FouleeFont.footnote.weight(.semibold))
                                .foregroundStyle(FouleeColor.accentMid)
                        }
                    }
                    Spacer()
                }
                .padding(14)
                .fouleeGlass(cornerRadius: 18)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                        row(workout, isLast: index == workouts.count - 1)
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FouleeFont.title3)
            HStack(spacing: 8) {
                if ring.minutes > 0 {
                    Text("\(durationText(minutes: ring.minutes)) d'activité")
                        .font(FouleeFont.footnote)
                        .foregroundStyle(.secondary)
                }
                if ring.minutes >= goalMinutes, ring.minutes > 0 {
                    Label("Objectif tenu", systemImage: FouleeIcon.check)
                        .font(FouleeFont.footnote.weight(.semibold))
                        .foregroundStyle(FouleeColor.success)
                }
            }
        }
    }

    private func row(_ workout: WorkoutSummary, isLast: Bool) -> some View {
        let tint = workout.activity.tint
        return HStack(alignment: .top, spacing: 10) {
            // Shrunk rather than wrapped: « 12:05 PM » is wider than the
            // column « 12:05 » was sized for (issue #594).
            Text(workout.startedAt.clockText)
                .font(FouleeFont.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 42, alignment: .trailing)
                .padding(.top, 16)
            VStack(spacing: 0) {
                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)
                    .padding(.top, 19)
                Rectangle()
                    .fill(isLast ? Color.clear : Color.gray.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            NavigationLink(value: workout) {
                card(workout, tint: tint)
            }
            .buttonStyle(.pressable)
            .padding(.bottom, isLast ? 0 : 12)
        }
    }

    /// « 5,2 km · ↑ 120 m · ↓ 115 m · 142 kcal · Garmin Connect »: the climb
    /// and the descent beside the distance, when the source wrote them (#537,
    /// #565). On two lines it breaks between figures, never inside one: no
    /// « 310 » left above its « kcal » (issue #594).
    private func figures(of workout: WorkoutSummary, spoken: Bool = false) -> String {
        let climb = spoken ? workout.climbSpokenText : workout.climbText
        let descent = spoken ? workout.descentSpokenText : workout.descentText
        return [workout.distanceKm.kmText(fractionDigits: 1), climb, descent, workout.caloriesText, workout.sourceName]
            .compactMap { $0?.replacingOccurrences(of: " ", with: "\u{00A0}") }
            .joined(separator: " · ")
    }

    private func card(_ workout: WorkoutSummary, tint: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.18))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: workout.activityIcon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(tint)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.activityLabel)
                    .font(FouleeFont.headline)
                    .foregroundStyle(.primary)
                Text(figures(of: workout))
                    .accessibilityLabel(figures(of: workout, spoken: true))
                    .font(FouleeFont.caption)
                    .foregroundStyle(.secondary)
                    // Two lines: with a climb and a source, one line cut the
                    // calories and the source off, in French as in English.
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Text(durationText(minutes: Int(workout.durationSeconds / 60)))
                .scaledNumericFont(size: 18, weight: .semibold)
                .foregroundStyle(.primary)
            Image(systemName: "chevron.right")
                .font(FouleeFont.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .fouleeGlass(cornerRadius: 20)
    }

    // MARK: - A day without an outing (issue #443)

    private var isToday: Bool {
        Calendar.current.isDate(outings.day, inSameDayAs: date.now)
    }

    private var emptyIcon: String {
        guard ring.isPlanned else { return "cup.and.saucer" }
        return isToday ? FouleeIcon.mixedCardio : "moon.zzz"
    }

    /// Today is still open: it is « pas encore », not « aucune ».
    private var emptyTitle: LocalizedStringResource {
        guard ring.isPlanned else { return "Jour de repos : rien de prévu" }
        return isToday ? "Pas encore de sortie aujourd'hui" : "Aucune séance enregistrée"
    }

    /// What is left to do today, the question the Bilan is opened with at
    /// midday. Nothing on a past day: it can no longer change.
    private var emptyHint: LocalizedStringResource? {
        guard isToday, ring.isPlanned, ring.minutes < goalMinutes else { return nil }
        return "Encore \(durationText(minutes: goalMinutes - ring.minutes)) pour ton objectif"
    }

    private var title: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date.now)
        if calendar.isDate(outings.day, inSameDayAs: today) { return String(localized: "Aujourd'hui") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(outings.day, inSameDayAs: yesterday) { return String(localized: "Hier") }
        return outings.day.dayText.capitalized(with: .app)
    }
}
