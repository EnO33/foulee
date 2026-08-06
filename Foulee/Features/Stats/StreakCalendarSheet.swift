import Dependencies
import SwiftUI

/// Streak view opened from the Série card. Fitness-style: a flame hero, a
/// progress bar toward the record, and a swipeable month browser whose stats
/// and daily rings follow the month on screen (tap a day for its detail).
struct StreakCalendarSheet: View {
    var onClose: () -> Void

    @State private var store: StreakCalendarStore

    init(goalMinutes: Int, goalSteps: Int, activeDays: Set<Weekday>, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _store = State(initialValue: StreakCalendarStore(
            goalMinutes: goalMinutes,
            goalSteps: goalSteps,
            activeDays: activeDays
        ))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SheetBackground()
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    recordCard
                    monthCard
                    if !store.isLoading && !store.months.isEmpty {
                        totalsCard
                        weekdayCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            closeButton.padding(20)
        }
        .task { await store.load() }
    }

    private var hero: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(FouleeColor.streakGradient)
                .frame(width: 76, height: 76)
                .overlay {
                    Image(systemName: FouleeIcon.flame)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: Color(hex: 0xFF6B00).opacity(0.35), radius: 18, y: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("SÉRIE ACTUELLE")
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(store.currentStreak)")
                        .scaledNumericFont(size: 44)
                    Text("jours")
                        .font(FouleeFont.title3)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 48)
    }

    private var recordCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(recordTitle)
                    .font(FouleeFont.headline)
                Spacer()
                if store.bestStreak > 0 {
                    Text("\(store.currentStreak) / \(store.bestStreak)")
                        .scaledNumericFont(size: 16, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressBar(fraction: recordFraction)
                .frame(height: 10)
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 22)
    }

    private var recordTitle: String {
        let current = store.currentStreak
        let record = store.bestStreak
        if record == 0 { return "Lance ta première série 🔥" }
        if current >= record { return "🔥 Nouveau record !" }
        let remaining = record - current
        return "Plus que \(remaining) \(remaining == 1 ? "jour" : "jours") pour ton record"
    }

    private var recordFraction: Double {
        let current = Double(store.currentStreak)
        let record = Double(store.bestStreak)
        if record > 0 { return min(current / record, 1) }
        return current > 0 ? 1 : 0
    }

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 260)
            } else if store.months.isEmpty {
                Text("Pas encore de données")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                StreakMonthBrowser(
                    months: store.months,
                    goalMinutes: store.goalMinutes,
                    goalSteps: store.goalSteps
                )
            }
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 24)
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("12 derniers mois")
                .font(FouleeFont.headline)
            HStack(spacing: 0) {
                totalCell(value: "\(store.totalWalks)", label: store.totalWalks == 1 ? "sortie" : "sorties")
                divider
                totalCell(value: formattedDuration(store.totalMinutes), label: "d'activité")
                divider
                totalCell(value: "\(store.overallRate) %", label: "réussite")
            }
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 22)
    }

    private func totalCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .scaledNumericFont(size: 20, weight: .semibold)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var divider: some View {
        Rectangle().fill(Color.gray.opacity(0.25)).frame(width: 1, height: 34)
    }

    private func formattedDuration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let mins = minutes % 60
        return mins == 0 ? "\(hours) h" : "\(hours) h \(mins)"
    }

    private var weekdayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tes jours les plus réguliers")
                .font(FouleeFont.headline)
            StreakWeekdayBreakdown(stats: store.weekdayStats)
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 22)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Fermer")
    }
}

/// Rounded track + fill progress bar used by the record card.
private struct ProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.16))
                Capsule()
                    .fill(FouleeColor.streakGradient)
                    .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), 0))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct StreakCalendarPreview: View {
    init() { prepareDependencies { $0.healthKit = .previewValue } }
    var body: some View {
        StreakCalendarSheet(goalMinutes: 20, goalSteps: 6_000, activeDays: Weekday.workWeek, onClose: {})
    }
}

#Preview { StreakCalendarPreview() }
