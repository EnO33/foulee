import SwiftUI

/// Hero card at the top of `WorkoutDetailSheet` — the session's own figure,
/// date label, big duration, then a one-liner naming the sport, the time range
/// and the source (issue #245).
struct WorkoutDetailHero: View {
    let detail: WorkoutDetail

    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(FouleeColor.accentMid.opacity(0.18))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: detail.summary.activity.icon)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(FouleeColor.accentMid)
                }
            Text(dateLabel)
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.1)
            Text(durationText)
                .scaledNumericFont(size: 44)
            Text("\(detail.summary.activity.label) · \(timeRange) · \(detail.summary.sourceName)")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .fouleeGlass(cornerRadius: 26)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var dateLabel: String {
        let calendar = Calendar.current
        let date = detail.summary.startedAt
        if calendar.isDateInToday(date) { return "Aujourd'hui" }
        if calendar.isDateInYesterday(date) { return "Hier" }
        return Self.dayFormatter.string(from: date).uppercased()
    }

    private var timeRange: String {
        "\(Self.timeFormatter.string(from: detail.summary.startedAt)) → \(Self.timeFormatter.string(from: detail.summary.endedAt))"
    }

    private var durationText: String {
        let total = Int(detail.summary.durationSeconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
