import SwiftUI

/// The daily-rings grid for the streak view: a 7-column month of rings filled
/// by minutes / goal, with a drag/tap to inspect a single day. Extracted from
/// `StreakCalendarSheet` so each type stays small.
struct StreakRingsGrid: View {
    let days: [CalendarDay]
    let goalMinutes: Int

    @State private var selectedDay: CalendarDay?
    private let weekdayLabels = ["L", "M", "M", "J", "V", "S", "D"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailLine
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label).font(FouleeFont.caption).foregroundStyle(.secondary)
                }
            }
            grid
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(days) { ring($0) }
        }
        .overlay {
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
        .accessibilityLabel("Calendrier de série du dernier mois")
        .accessibilityValue("\(days.filter { $0.status == .done }.count) jours réussis")
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
                Text("Glisse ton doigt sur le calendrier pour le détail d'un jour")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 20, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            if isSelected {
                Circle().strokeBorder(FouleeColor.accentMid, lineWidth: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }

    /// Map a touch point to the day under the finger (7-column grid).
    private func select(at location: CGPoint, in size: CGSize) {
        let spacing: CGFloat = 8
        let cell = (size.width - spacing * 6) / 7
        let step = cell + spacing
        guard step > 0 else { return }
        let col = Int(location.x / step)
        let row = Int(location.y / step)
        guard (0..<7).contains(col), row >= 0 else { return }
        let index = row * 7 + col
        if days.indices.contains(index) { selectedDay = days[index] }
    }

    private func detailText(_ day: CalendarDay) -> String {
        switch day.status {
        case .done: "\(day.minutes) min · objectif atteint"
        case .missed: "\(day.minutes) / \(goalMinutes) min"
        case .rest: "jour de repos"
        case .future: "à venir"
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
