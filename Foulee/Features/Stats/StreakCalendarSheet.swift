import Dependencies
import SwiftUI

/// Streak calendar, opened by tapping the Série card — a heatmap of done /
/// missed / rest days over the last ~3 months, plus the current streak and
/// record. Presented as a sheet.
struct StreakCalendarSheet: View {
    var onClose: () -> Void

    @State private var store: StreakCalendarStore
    private let weekdayLabels = ["L", "M", "M", "J", "V", "S", "D"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

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
                    calendarCard
                    legend
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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(FouleeColor.streakGradient)
                .frame(width: 66, height: 66)
                .overlay {
                    Image(systemName: FouleeIcon.flame)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("SÉRIE ACTUELLE")
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(store.currentStreak)")
                        .font(FouleeFont.numeric(size: 38))
                    Text("jours d'affilée")
                        .font(FouleeFont.callout)
                        .foregroundStyle(.secondary)
                }
                Text("Record : \(store.bestStreak) jours")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 48)
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("3 derniers mois")
                .font(FouleeFont.headline)
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(FouleeFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(store.days) { day in
                        cell(day)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Calendrier de série")
                .accessibilityValue("\(store.completedCount) jours réussis sur les 3 derniers mois")
            }
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 24)
    }

    private func cell(_ day: CalendarDay) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color(for: day.status))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if Calendar.current.isDateInToday(day.date) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(FouleeColor.accentMid, lineWidth: 1.5)
                }
            }
    }

    private func color(for status: DayStatus) -> Color {
        switch status {
        case .done: FouleeColor.accentMid
        case .missed: FouleeColor.danger.opacity(0.22)
        case .rest: Color.gray.opacity(0.12)
        case .future: Color.gray.opacity(0.05)
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: FouleeColor.accentMid, label: "Fait")
            legendItem(color: FouleeColor.danger.opacity(0.22), label: "Manqué")
            legendItem(color: Color.gray.opacity(0.12), label: "Repos")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(FouleeFont.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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

private struct StreakCalendarPreview: View {
    init() { prepareDependencies { $0.healthKit = .previewValue } }
    var body: some View {
        StreakCalendarSheet(goalMinutes: 20, activeDays: Weekday.workWeek, onClose: {})
    }
}

#Preview { StreakCalendarPreview() }
