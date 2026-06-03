import SwiftUI

/// One calendar month rendered as weekday-aligned daily rings (filled by
/// minutes / goal). Tap a day to select it — the selected ring gets an accent
/// outline. `nil` cells are the leading/trailing blanks that keep columns
/// aligned and the grid a stable 6 rows tall. Paged by `StreakMonthBrowser`.
struct StreakMonthRings: View {
    let month: StreakMonth
    let goalMinutes: Int
    @Binding var selectedDay: CalendarDay?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(month.cells.enumerated()), id: \.offset) { _, cell in
                if let day = cell {
                    ring(day)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedDay = day }
                } else {
                    Color.clear.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calendrier de \(month.title)")
        .accessibilityValue("\(month.walks) jours réussis")
    }

    private func ring(_ day: CalendarDay) -> some View {
        let progress = goalMinutes > 0 ? min(Double(day.minutes) / Double(goalMinutes), 1) : 0
        let isSelected = selectedDay?.id == day.id
        return ZStack {
            switch day.status {
            case .rest:
                Circle().fill(Color.gray.opacity(0.18)).frame(width: 6, height: 6)
            case .future:
                Circle().strokeBorder(Color.gray.opacity(0.12), lineWidth: 3)
            case .done, .missed:
                Circle().strokeBorder(Color.gray.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(progress, 0.02))
                    .stroke(FouleeColor.accentGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if Calendar.current.isDateInToday(day.date) {
                Circle().fill(FouleeColor.accentMid).frame(width: 5, height: 5)
            }
        }
        .padding(2)
        .overlay {
            if isSelected { Circle().strokeBorder(FouleeColor.accentMid, lineWidth: 2) }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }
}
