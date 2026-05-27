import Dependencies
import SwiftUI

/// Modal sheet presented when the user taps "Voir le résumé" — shows the
/// last 7 days of walking workouts, grouped by day with today first.
/// Days without a recorded walk get a discreet placeholder so the user
/// also sees what they missed.
struct TodayWorkoutsSheet: View {
    private static let daysBack = 7

    @Environment(\.dismiss) private var dismiss

    @Dependency(\.healthKit) private var healthKit

    @State private var workouts: [WorkoutSummary] = []
    @State private var isLoading = true
    @State private var lastError: String?
    @State private var selectedWorkout: WorkoutSummary?

    var body: some View {
        NavigationStack {
            ZStack {
                Wallpaper()
                content
            }
            .navigationTitle("Résumé 7 jours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(FouleeColor.accentMid)
                }
            }
        }
        .task { await load() }
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailSheet(summary: workout)
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
                    ForEach(daySections, id: \.day) { section in
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
                    Button {
                        selectedWorkout = workout
                    } label: {
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
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text("Aucune marche enregistrée")
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
                    .font(FouleeFont.numeric(size: 22, weight: .semibold))
            }
            HStack(spacing: 0) {
                metricCell(
                    icon: FouleeIcon.distance,
                    value: distanceText(workout.distanceKm),
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(FouleeFont.numeric(size: 18, weight: .semibold))
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
            workouts = try await healthKit.recentWorkouts(Self.daysBack)
        } catch {
            lastError = error.localizedDescription
            workouts = []
        }
    }

    // MARK: - Grouping

    private var daySections: [(day: Date, workouts: [WorkoutSummary])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dayStarts = (0..<Self.daysBack).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
        let byDay = Dictionary(grouping: workouts) {
            calendar.startOfDay(for: $0.startedAt)
        }
        return dayStarts.map { day in
            (day: day, workouts: byDay[day] ?? [])
        }
    }

    // MARK: - Formatting

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(date) { return "Hier" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date)
    }

    private func timeRange(_ workout: WorkoutSummary) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: workout.startedAt)) → \(formatter.string(from: workout.endedAt))"
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

    private func distanceText(_ km: Double) -> String {
        String(format: "%.2f km", km).replacingOccurrences(of: ".", with: ",")
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
