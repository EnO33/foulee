import SwiftUI

/// Month-by-month view of the streak rings. The chevrons move between months
/// (the title, stats and rings all follow); slide a finger across the rings —
/// or tap — to inspect a single day, with a light haptic tick on each change.
struct StreakMonthBrowser: View {
    let months: [StreakMonth]
    let goalMinutes: Int
    let goalSteps: Int

    @State private var index: Int
    @State private var selectedDay: CalendarDay?

    init(months: [StreakMonth], goalMinutes: Int, goalSteps: Int) {
        self.months = months
        self.goalMinutes = goalMinutes
        self.goalSteps = goalSteps
        // Start on the current month (last) rather than flashing the oldest.
        _index = State(initialValue: max(months.count - 1, 0))
    }

    private let weekdayLabels = ["L", "M", "M", "J", "V", "S", "D"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private var month: StreakMonth? { months.indices.contains(index) ? months[index] : months.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statsRow
            weekdayHeader
            rings
            detailLine
        }
        .sensoryFeedback(.selection, trigger: selectedDay?.id)
    }

    private var header: some View {
        HStack {
            chevron("chevron.left", label: "Mois précédent", enabled: index > 0) { step(-1) }
            Spacer(minLength: 0)
            Text(month?.title ?? "")
                .font(FouleeFont.headline)
            Spacer(minLength: 0)
            chevron("chevron.right", label: "Mois suivant", enabled: index < months.count - 1) { step(1) }
        }
    }

    private func chevron(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: "\(month?.rate ?? 0) %", label: "Réussite")
            divider
            statCell(value: "\(month?.walks ?? 0)", label: (month?.walks ?? 0) == 1 ? "marche" : "marches")
            divider
            statCell(value: "\(month?.minutes ?? 0)", label: "minutes")
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(FouleeFont.numeric(size: 19, weight: .semibold))
            Text(label).font(FouleeFont.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var divider: some View {
        Rectangle().fill(Color.gray.opacity(0.22)).frame(width: 1, height: 30)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                Text(label).font(FouleeFont.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var rings: some View {
        Group {
            if let month {
                StreakMonthRings(
                    month: month,
                    goalMinutes: goalMinutes,
                    goalSteps: goalSteps,
                    selectedDay: $selectedDay
                )
                .id(month.id)
                .transition(.opacity)
            }
        }
    }

    private var detailLine: some View {
        Group {
            if let day = selectedDay {
                HStack(spacing: 8) {
                    Circle().fill(color(for: day.status)).frame(width: 9, height: 9)
                    Text(Self.dayFormatter.string(from: day.date).capitalized)
                        .font(FouleeFont.footnote.weight(.semibold))
                    Text("·").foregroundStyle(.secondary)
                    Text(detailText(day)).font(FouleeFont.footnote).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            } else {
                Text("Glisse ton doigt sur les jours pour le détail")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 20, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard months.indices.contains(next) else { return }
        selectedDay = nil
        withAnimation(.easeInOut(duration: 0.2)) { index = next }
    }

    private func detailText(_ day: CalendarDay) -> String {
        let steps = "\(day.steps.formattedFR) pas"
        switch day.status {
        case .done: return "\(day.minutes) min · \(steps)"
        case .missed: return "\(day.minutes) / \(goalMinutes) min · \(steps)"
        case .rest: return day.steps > 0 ? "Repos · \(steps)" : "Jour de repos"
        case .future: return "À venir"
        }
    }

    private func color(for status: DayStatus) -> Color {
        switch status {
        case .done: FouleeColor.accentMid
        case .missed: FouleeColor.danger
        case .rest: Color.gray
        case .future: Color.gray.opacity(0.5)
        }
    }
}
