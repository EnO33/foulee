import Dependencies
import SwiftUI

/// The day picked in the Bilan (issues #348, #350): how it went against the
/// goal, then its outings on a timeline, each at its hour, in its sport's
/// colour, opening its detail.
struct RecapDayTimeline: View {
    let outings: OutingDay
    let ring: Recap.Day
    let goalMinutes: Int

    @Dependency(\.date) private var date

    private var sorted: [WorkoutSummary] {
        outings.workouts.sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if sorted.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: ring.isPlanned ? "moon.zzz" : "cup.and.saucer")
                        .scaledSystemFont(size: 18)
                        .foregroundStyle(.secondary)
                    Text(ring.isPlanned ? "Aucune séance enregistrée" : "Jour de repos : rien de prévu")
                        .font(FouleeFont.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(14)
                .fouleeGlass(cornerRadius: 18)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, workout in
                        row(workout, isLast: index == sorted.count - 1)
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
                    Text("\(ring.minutes) min d'activité")
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
            Text(workout.startedAt.clockText)
                .font(FouleeFont.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
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
                Text("\(workout.distanceKm.kmText(fractionDigits: 1)) · \(workout.activeCalories) kcal · \(workout.sourceName)")
                    .font(FouleeFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(Int(workout.durationSeconds / 60)) min")
                .scaledNumericFont(size: 18, weight: .semibold)
                .foregroundStyle(.primary)
            Image(systemName: "chevron.right")
                .font(FouleeFont.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .fouleeGlass(cornerRadius: 20)
    }

    private var title: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date.now)
        if calendar.isDate(outings.day, inSameDayAs: today) { return "Aujourd'hui" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(outings.day, inSameDayAs: yesterday) { return "Hier" }
        return Self.titleFormatter.string(from: outings.day).capitalized(with: Locale(identifier: "fr_FR"))
    }

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()
}
