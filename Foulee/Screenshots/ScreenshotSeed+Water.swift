#if DEBUG
import Foundation

/// The seeded water (issue #355): today's glasses, which add up to `waterML`,
/// and the six days before for the Hydratation screen's week.
extension ScreenshotSeed {
    /// Minutes after midnight, amount, writer — oldest first, all before the
    /// pinned 14:35.
    private static let glasses: [(minutes: Int, milliliters: Int, source: String)] = [
        (8 * 60 + 10, 250, "Foulée"),
        (10 * 60 + 5, 250, "Apple Watch"),
        (11 * 60 + 40, 500, "Foulée"),
        (13 * 60 + 15, 250, "Foulée"),
        (14 * 60 + 20, 250, "Apple Watch")
    ]

    /// The six days before today, oldest first: four that held the 2 L goal.
    private static let pastDaysML = [1_750, 2_000, 2_250, 1_250, 2_000, 2_250]

    static var waterToday: [WaterSample] {
        glasses.enumerated().map { index, glass in
            WaterSample(
                id: UUID(uuidString: "5C0EE7ED-0000-4000-9000-\(String(format: "%012d", index))") ?? UUID(),
                date: today.addingTimeInterval(TimeInterval(glass.minutes * 60)),
                milliliters: glass.milliliters,
                sourceName: glass.source
            )
        }
    }

    static func waterSeries(daysBack: Int) -> [MetricPoint] {
        let values = pastDaysML + [waterML]
        return (0..<max(daysBack, 0)).reversed().map { offset in
            let index = values.count - 1 - offset
            return MetricPoint(date: day(offset: offset), value: Double(values.indices.contains(index) ? values[index] : 0))
        }
    }
}
#endif
