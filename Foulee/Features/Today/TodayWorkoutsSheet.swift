import Dependencies
import SwiftUI

/// Modal sheet presented when the user taps "Voir le résumé" — shows the
/// last 7 days of workouts (see `WorkoutActivityFilter`), grouped by day
/// with today first. Days without a recorded session get a discreet
/// placeholder so the user also sees what they missed.
struct TodayWorkoutsSheet: View {
    private static let daysBack = 7

    @Environment(\.dismiss) private var dismiss

    @Dependency(\.healthKit) private var healthKit

    @State private var sections: [DaySection] = []
    @State private var isLoading = true
    @State private var lastError: String?

    struct DaySection: Identifiable {
        let day: Date
        let workouts: [WorkoutSummary]
        var id: Date { day }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Résumé 7 jours")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: WorkoutSummary.self) { workout in
                    WorkoutDetailSheet(summary: workout)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer") { dismiss() }
                            .foregroundStyle(FouleeColor.accentMid)
                    }
                }
        }
        .presentationBackground { SheetBackground() }
        .task {
            // Let the slide-up animation finish before kicking off the
            // HealthKit query — otherwise the query competes with the
            // animation's MainActor work and visibly stutters the slide.
            try? await Task.sleep(for: .milliseconds(300))
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .controlSize(.large)
                .tint(FouleeColor.accentMid)
        } else {
            ScrollView {
                VStack(spacing: 22) {
                    ForEach(sections) { section in
                        daySectionView(day: section.day, workouts: section.workouts)
                    }
                    healthAppLink
                        .padding(.top, 4)
                    if let lastError {
                        Text(lastError)
                            .font(FouleeFont.footnote)
                            .foregroundStyle(FouleeColor.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }

    private func daySectionView(day: Date, workouts: [WorkoutSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dayLabel(day).uppercased())
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.1)
                .padding(.leading, 4)

            if workouts.isEmpty {
                emptyDayCard
            } else {
                ForEach(workouts) { workout in
                    NavigationLink(value: workout) {
                        workoutCard(workout)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private var emptyDayCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .scaledSystemFont(size: 18)
                .foregroundStyle(.secondary)
            // "Aucune marche" was the placeholder's exact contradiction for a
            // runner (#217): the filter now lists runs and hikes too, so the
            // empty day has to speak about sessions, not walks.
            Text("Aucune séance enregistrée")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .fouleeGlass(cornerRadius: 18)
    }

    private func workoutCard(_ workout: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FouleeColor.accentMid.opacity(0.18))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "figure.walk.motion")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(FouleeColor.accentMid)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeRange(workout))
                        .font(FouleeFont.headline)
                    Text(workout.sourceName)
                        .font(FouleeFont.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(durationText(workout.durationSeconds))
                    .scaledNumericFont(size: 22, weight: .semibold)
            }
            HStack(spacing: 0) {
                metricCell(
                    icon: FouleeIcon.distance,
                    value: workout.distanceKm.kmText(),
                    label: "Distance"
                )
                divider
                metricCell(
                    icon: FouleeIcon.flame,
                    value: "\(workout.activeCalories) kcal",
                    label: "Calories"
                )
                divider
                metricCell(
                    icon: FouleeIcon.timer,
                    value: minutesText(workout.durationSeconds),
                    label: "Minutes"
                )
            }
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 22)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.25))
            .frame(width: 1, height: 36)
    }

    private func metricCell(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .scaledSystemFont(size: 14, weight: .semibold)
                .foregroundStyle(.secondary)
            Text(value)
                .scaledNumericFont(size: 18, weight: .semibold)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var healthAppLink: some View {
        Button {
            if let url = URL(string: "x-apple-health://") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                Text("Voir dans Santé")
            }
            .font(FouleeFont.footnote.weight(.semibold))
            .foregroundStyle(FouleeColor.accentMid)
        }
        .buttonStyle(.pressable)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let workouts = try await healthKit.recentWorkouts(Self.daysBack)
            // Group once, here — not in a `body`-evaluated computed property.
            sections = Self.groupByDay(workouts)
        } catch {
            lastError = error.localizedDescription
            sections = []
        }
    }

    // MARK: - Grouping

    private static func groupByDay(_ workouts: [WorkoutSummary]) -> [DaySection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dayStarts = (0..<daysBack).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
        let byDay = Dictionary(grouping: workouts) {
            calendar.startOfDay(for: $0.startedAt)
        }
        return dayStarts.map { day in
            DaySection(day: day, workouts: byDay[day] ?? [])
        }
    }

    // MARK: - Formatting

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(date) { return "Hier" }
        return Self.dayFormatter.string(from: date)
    }

    private func timeRange(_ workout: WorkoutSummary) -> String {
        "\(Self.timeFormatter.string(from: workout.startedAt)) → \(Self.timeFormatter.string(from: workout.endedAt))"
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func minutesText(_ seconds: TimeInterval) -> String {
        "\(Int(seconds / 60)) min"
    }

}

private struct TodayWorkoutsSheetPreview: View {
    init() {
        prepareDependencies { $0.healthKit = .previewValue }
    }
    var body: some View {
        Color.clear.sheet(isPresented: .constant(true)) {
            TodayWorkoutsSheet()
        }
    }
}

#Preview { TodayWorkoutsSheetPreview() }
