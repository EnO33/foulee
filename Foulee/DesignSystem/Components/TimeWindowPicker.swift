import FouleeKit
import SwiftUI

/// A start and an end time on one line (issue #395) — the outing window, the
/// hydration window. The end can't be set before the start, nor the start
/// after the end: each picker is bounded by the other, so an inverted window
/// is never written in the first place.
struct TimeWindowPicker: View {
    @Binding var start: TimeOfDay
    @Binding var end: TimeOfDay

    private static let minimumGap = TimeInterval(TimeOfDay.minimumWindowMinutes * 60)

    var body: some View {
        let startDate = start.dateToday()
        let endDate = end.dateToday()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: startDate)
        let dayEnd = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: startDate) ?? endDate
        HStack(spacing: 16) {
            picker(
                "Début",
                selection: Binding(get: { startDate }, set: { start = TimeOfDay(date: $0) }),
                in: Self.range(dayStart, endDate.addingTimeInterval(-Self.minimumGap))
            )
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 2)
                .clipShape(Capsule())
                .accessibilityHidden(true)
            picker(
                "Fin",
                alignment: .trailing,
                selection: Binding(get: { endDate }, set: { end = TimeOfDay(date: $0) }),
                in: Self.range(startDate.addingTimeInterval(Self.minimumGap), dayEnd)
            )
        }
    }

    /// `lower...upper`, collapsed onto `lower` rather than trapping when a
    /// window stored before the bounds existed is already inverted.
    private static func range(_ lower: Date, _ upper: Date) -> ClosedRange<Date> {
        lower...max(lower, upper)
    }

    private func picker(
        _ label: String,
        alignment: HorizontalAlignment = .leading,
        selection: Binding<Date>,
        in range: ClosedRange<Date>
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(label)
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // Labelled even though the label is hidden: VoiceOver reads it.
            DatePicker(label, selection: selection, in: range, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}
