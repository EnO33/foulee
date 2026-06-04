import SwiftUI

/// One calendar month rendered as weekday-aligned daily rings (filled by
/// minutes / goal). Slide a finger across the grid — or tap — to select a day;
/// the selected ring gets an accent outline and the browser ticks a haptic on
/// each change. `nil` cells are the leading/trailing blanks that keep columns
/// aligned and the grid a stable 6 rows tall.
struct StreakMonthRings: View {
    let month: StreakMonth
    let goalMinutes: Int
    @Binding var selectedDay: CalendarDay?

    private let spacing: CGFloat = 8
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(Array(month.cells.enumerated()), id: \.offset) { _, cell in
                if let day = cell {
                    ring(day)
                } else {
                    Color.clear.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .overlay {
            // One gesture handles both a tap and a finger-scrub across rings.
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { select(at: $0.location, in: geo.size) }
                    )
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

    /// Map a touch point to the day under the finger (square 7-column grid).
    /// Skips the blank padding cells and only writes on a real change so the
    /// haptic ticks once per ring.
    private func select(at location: CGPoint, in size: CGSize) {
        let cell = (size.width - spacing * 6) / 7
        let step = cell + spacing
        guard step > 0 else { return }
        let col = Int(location.x / step)
        let row = Int(location.y / step)
        guard (0..<7).contains(col), row >= 0 else { return }
        let index = row * 7 + col
        guard month.cells.indices.contains(index), let day = month.cells[index] else { return }
        if selectedDay?.id != day.id { selectedDay = day }
    }
}
