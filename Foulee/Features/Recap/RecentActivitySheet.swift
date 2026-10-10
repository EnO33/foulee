import Dependencies
import SwiftUI

/// The last seven days (issue #348), in the recap's language: the ring and the
/// verdict over the seven days, a strip of day rings to pick one, and the
/// picked day's outings on a timeline. It took the place of the « Résumé 7
/// jours » list.
struct RecentActivitySheet: View {
    let goalMinutes: Int
    let activeDays: Set<Weekday>

    @Environment(\.dismiss) private var dismiss
    @State private var store = RecentActivityStore()
    @State private var selectedDay: Date?
    @State private var isRevealed = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("7 derniers jours")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: WorkoutSummary.self) { WorkoutDetailSheet(summary: $0) }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer") { dismiss() }
                            .foregroundStyle(FouleeColor.accentMid)
                    }
                }
        }
        .presentationBackground { SheetBackground() }
        .task {
            // Let the slide-up finish before the HealthKit queries compete
            // with it on the main actor.
            try? await Task.sleep(for: .milliseconds(300))
            await store.load(goalMinutes: goalMinutes, activeDays: activeDays)
            selectedDay = store.days.first?.day
            withAnimation(.easeOut(duration: 0.8)) { isRevealed = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let recap = store.recap {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    RecapHero(recap: recap, isRevealed: isRevealed)
                    dayStrip(recap)
                    if let day = store.days.first(where: { $0.day == selectedDay }),
                       let ring = recap.days.first(where: { $0.date == day.day }) {
                        RecentDayTimeline(outings: day, ring: ring, goalMinutes: recap.goalMinutes)
                            .id(day.day)
                            .transition(.opacity)
                    }
                    if !recap.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Par rapport aux 7 jours d'avant")
                                .font(FouleeFont.headline)
                            RecapComparison(recap: recap, isRevealed: isRevealed)
                        }
                        .padding(16)
                        .fouleeGlass(cornerRadius: 22)
                    }
                    healthAppLink
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        } else if store.lastError != nil {
            Label("Impossible de lire tes données Santé pour le moment.", systemImage: "exclamationmark.triangle")
                .font(FouleeFont.callout)
                .foregroundStyle(.secondary)
                .padding(32)
        } else {
            ProgressView()
                .controlSize(.large)
                .tint(FouleeColor.accentMid)
        }
    }

    /// The seven days, oldest on the left, today on the right — a ring each,
    /// to pick the day the timeline shows.
    private func dayStrip(_ recap: Recap) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(recap.days.enumerated()), id: \.element.id) { index, day in
                let isSelected = day.date == selectedDay
                Button {
                    withAnimation(.snappy) { selectedDay = day.date }
                } label: {
                    VStack(spacing: 6) {
                        RecapDayRing(day: day, goalMinutes: recap.goalMinutes, lineWidth: 4.5, isRevealed: isRevealed)
                            .animation(.easeOut(duration: 0.6).delay(Double(index) * 0.05), value: isRevealed)
                        Text(Self.letterFormatter.string(from: day.date).uppercased())
                            .font(FouleeFont.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? FouleeColor.accentMid : .secondary)
                        Text(Self.numberFormatter.string(from: day.date))
                            .font(FouleeFont.caption.monospacedDigit())
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? FouleeColor.accentMid.opacity(0.14) : .clear)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Self.dayFormatter.string(from: day.date))
                .accessibilityValue("\(day.minutes) minutes")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(8)
        .fouleeGlass(cornerRadius: 22)
    }

    private var healthAppLink: some View {
        Button {
            if let url = URL(string: "x-apple-health://") {
                UIApplication.shared.open(url)
            }
        } label: {
            Label("Voir dans Santé", systemImage: "heart.fill")
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(FouleeColor.accentMid)
        }
        .buttonStyle(.pressable)
    }

    private static let french = Locale(identifier: "fr_FR")

    private static let letterFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = french
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    private static let numberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = french
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = french
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()
}

/// One day of the seven (issue #348): how it went against the goal, then its
/// outings on a timeline, each at its hour, in its sport's colour, opening its
/// detail.
private struct RecentDayTimeline: View {
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
