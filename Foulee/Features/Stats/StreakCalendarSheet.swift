import Dependencies
import SwiftUI

/// Streak view opened from the Série card. Fitness-style: a flame hero, a
/// progress bar toward the record, this month's stats, and the last month as
/// daily rings (filled by minutes / goal) you can scrub for per-day detail.
struct StreakCalendarSheet: View {
    var onClose: () -> Void

    @State private var store: StreakCalendarStore

    init(goalMinutes: Int, activeDays: Set<Weekday>, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _store = State(initialValue: StreakCalendarStore(goalMinutes: goalMinutes, activeDays: activeDays))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SheetBackground()
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    recordCard
                    monthStatsCard
                    ringsCard
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
                        .font(FouleeFont.numeric(size: 44))
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
                        .font(FouleeFont.numeric(size: 16, weight: .semibold))
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

    private var monthStatsCard: some View {
        let stats = monthStats
        return HStack(spacing: 0) {
            statCell(value: "\(stats.rate) %", label: "Réussite ce mois")
            divider
            statCell(value: "\(stats.walks)", label: "Marches")
            divider
            statCell(value: "\(store.bestStreak) j", label: "Record")
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 22)
    }

    private var monthStats: (rate: Int, walks: Int) {
        let calendar = Calendar.current
        let now = Date.now
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        let inMonth = store.days.filter {
            calendar.component(.month, from: $0.date) == month
                && calendar.component(.year, from: $0.date) == year
        }
        let active = inMonth.filter { $0.status == .done || $0.status == .missed }
        let done = inMonth.filter { $0.status == .done }.count
        let rate = active.isEmpty ? 0 : Int((Double(done) / Double(active.count) * 100).rounded())
        return (rate, done)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(FouleeFont.numeric(size: 20, weight: .semibold))
            Text(label)
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var divider: some View {
        Rectangle().fill(Color.gray.opacity(0.25)).frame(width: 1, height: 34)
    }

    private var ringsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dernier mois")
                .font(FouleeFont.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if store.isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else {
                StreakRingsGrid(days: store.days, goalMinutes: store.goalMinutes)
            }
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 24)
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
        StreakCalendarSheet(goalMinutes: 20, activeDays: Weekday.workWeek, onClose: {})
    }
}

#Preview { StreakCalendarPreview() }
