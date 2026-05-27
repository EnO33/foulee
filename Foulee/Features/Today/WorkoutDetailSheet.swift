import Dependencies
import SwiftUI

/// Detail view for a single workout — opened by tapping a row in
/// `TodayWorkoutsSheet`. Pulls HR samples + step count from HealthKit
/// for the workout's exact window, plus derives pace from the summary.
struct WorkoutDetailSheet: View {
    let summary: WorkoutSummary

    @Environment(\.dismiss) private var dismiss
    @Dependency(\.healthKit) private var healthKit

    @State private var detail: WorkoutDetail?
    @State private var isLoading = true
    @State private var lastError: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Détail")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer") { dismiss() }
                            .foregroundStyle(FouleeColor.accentMid)
                    }
                }
        }
        .presentationBackground { SheetBackground() }
        .task {
            // Same anti-stutter as TodayWorkoutsSheet: wait for the
            // slide animation to finish before hitting HealthKit so the
            // query doesn't compete with the animation on the MainActor.
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
        } else if let detail {
            ScrollView {
                VStack(spacing: 16) {
                    hero(detail: detail)
                    if !detail.heartRateSamples.isEmpty {
                        heartRateSection(detail: detail)
                    }
                    metricsGrid(detail: detail)
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
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(FouleeColor.warning)
                Text("Détail indisponible")
                    .font(FouleeFont.headline)
                if let lastError {
                    Text(lastError)
                        .font(FouleeFont.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }

    private func hero(detail: WorkoutDetail) -> some View {
        WorkoutDetailHero(detail: detail)
    }

    private func heartRateSection(detail: WorkoutDetail) -> some View {
        WorkoutDetailHeartRate(detail: detail)
    }

    private func metricsGrid(detail: WorkoutDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STATS")
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                metricCard(
                    icon: FouleeIcon.distance,
                    tint: Color(hex: 0x0A84FF),
                    label: "Distance",
                    value: distanceText(detail.summary.distanceKm)
                )
                metricCard(
                    icon: FouleeIcon.footsteps,
                    tint: FouleeColor.accentMid,
                    label: "Pas",
                    value: detail.stepsCount.formattedFR
                )
                metricCard(
                    icon: FouleeIcon.flame,
                    tint: FouleeColor.warning,
                    label: "Calories",
                    value: "\(detail.summary.activeCalories) kcal"
                )
                metricCard(
                    icon: FouleeIcon.timer,
                    tint: FouleeColor.accentSecondary,
                    label: "Allure",
                    value: paceText(detail)
                )
            }
        }
    }

    private func metricCard(icon: String, tint: Color, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(FouleeFont.numeric(size: 22, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .fouleeGlass(cornerRadius: 18)
    }

    private var healthAppLink: some View {
        Button {
            if let url = URL(string: "x-apple-health://") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                Text("Ouvrir dans Santé")
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
            detail = try await healthKit.workoutDetail(summary)
        } catch {
            lastError = error.localizedDescription
            detail = nil
        }
    }

    // MARK: - Formatting

    private func distanceText(_ km: Double) -> String {
        String(format: "%.2f km", km).replacingOccurrences(of: ".", with: ",")
    }

    private func paceText(_ detail: WorkoutDetail) -> String {
        guard let minPerKm = detail.paceMinPerKm else { return "—" }
        let minutes = Int(minPerKm)
        let seconds = Int((minPerKm - Double(minutes)) * 60)
        return String(format: "%d′%02d″/km", minutes, seconds)
    }
}

private struct WorkoutDetailPreview: View {
    init() {
        prepareDependencies { $0.healthKit = .previewValue }
    }
    var body: some View {
        let summary = WorkoutSummary(
            id: UUID(),
            startedAt: Date().addingTimeInterval(-2 * 60 * 60),
            endedAt: Date().addingTimeInterval(-2 * 60 * 60 + 24 * 60),
            durationSeconds: 24 * 60,
            distanceKm: 1.8,
            activeCalories: 142,
            sourceName: "Apple Watch de Matthieu"
        )
        return Color.clear.sheet(isPresented: .constant(true)) {
            WorkoutDetailSheet(summary: summary)
        }
    }
}

#Preview { WorkoutDetailPreview() }
