import SwiftUI

/// One calendar month rendered as weekday-aligned daily rings. Each active day
/// is a Fitness-style double ring: outer = steps / step goal (purple), inner =
/// activity minutes / goal (green). Slide a finger across the grid — or tap —
/// to select a day; the selected day gets an accent outline and the browser
/// ticks a haptic on each change. `nil` cells are the leading/trailing blanks
/// that keep columns aligned and the grid a stable 6 rows tall.
struct StreakMonthRings: View {
    let month: StreakMonth
    let goalMinutes: Int
    let goalSteps: Int
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
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(scrubGesture(in: geo.size))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calendrier de \(month.title)")
        .accessibilityValue("\(month.walks) jours réussis")
    }

    private func ring(_ day: CalendarDay) -> some View {
        let isSelected = selectedDay?.id == day.id
        return ZStack {
            switch day.status {
            case .rest:
                // A visible neutral ring (not a tiny dot) so rest days read as
                // days — clearly lighter than active rings, darker than future.
                // The day detail labels them "jour de repos".
                Circle().strokeBorder(Color.gray.opacity(0.3), lineWidth: 2.5)
                Circle().fill(Color.gray.opacity(0.12)).padding(7)
            case .future:
                Circle().strokeBorder(Color.gray.opacity(0.12), lineWidth: 2.5)
            case .done, .missed:
                arc(progress: fraction(day.steps, goalSteps), gradient: FouleeColor.accentGradient)
                arc(progress: fraction(day.minutes, goalMinutes), gradient: FouleeColor.activityGradient)
                    .padding(5.5)
            }
            if Calendar.current.isDateInToday(day.date) {
                Circle().fill(FouleeColor.accentMid).frame(width: 4, height: 4)
            }
        }
        .padding(2)
        .overlay {
            if isSelected { Circle().strokeBorder(FouleeColor.accentMid, lineWidth: 2) }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }

    /// One ring of the double ring: a faint track plus the filled arc. An empty
    /// goal shows just the track; a non-zero fill keeps a small minimum sweep so
    /// it reads as "started".
    private func arc(progress: Double, gradient: LinearGradient) -> some View {
        ZStack {
            Circle().strokeBorder(Color.gray.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress > 0 ? max(progress, 0.04) : 0)
                .stroke(gradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private func fraction(_ value: Int, _ goal: Int) -> Double {
        goal > 0 ? min(max(Double(value) / Double(goal), 0), 1) : 0
    }

    /// A tap selects a day instantly; a brief press-then-drag scrubs across
    /// days (with the browser's haptic tick). Plain flicks aren't claimed, so
    /// the enclosing sheet keeps scrolling vertically over the grid.
    private func scrubGesture(in size: CGSize) -> some Gesture {
        let tap = SpatialTapGesture()
            .onEnded { select(at: $0.location, in: size) }
        let scrub = LongPressGesture(minimumDuration: 0.12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    select(at: drag.location, in: size)
                }
            }
        return tap.exclusively(before: scrub)
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
