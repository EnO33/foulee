import Foundation

/// Day-of-week aligned to Apple's "Lundi = first" convention, with French
/// short labels used by the onboarding chips and the Today week bars.
enum Weekday: Int, CaseIterable, Codable, Sendable, Identifiable {
    case monday = 1
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .monday: "L"
        case .tuesday: "M"
        case .wednesday: "M"
        case .thursday: "J"
        case .friday: "V"
        case .saturday: "S"
        case .sunday: "D"
        }
    }

    /// Default "weekday" set used at onboarding (Mon → Fri).
    static let workWeek: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    /// This day in `Calendar`'s numbering (1 = Sunday … 7 = Saturday), to feed
    /// `StreakCalculator` and `Calendar.component(.weekday:)`.
    var calendarWeekday: Int { (rawValue % 7) + 1 }
}

extension Set where Element == Weekday {
    /// Compact bitmask (7 bits, Monday is bit 0) for UserDefaults storage.
    var bitmask: Int {
        reduce(0) { acc, day in acc | (1 << (day.rawValue - 1)) }
    }

    init(bitmask: Int) {
        self = Set(Weekday.allCases.filter { bitmask & (1 << ($0.rawValue - 1)) != 0 })
    }

    /// The set mapped to `Calendar` weekday numbers — what `StreakCalculator`
    /// expects for `activeWeekdays`.
    var calendarWeekdays: Set<Int> {
        var result = Set<Int>()
        for day in self { result.insert(day.calendarWeekday) }
        return result
    }
}
