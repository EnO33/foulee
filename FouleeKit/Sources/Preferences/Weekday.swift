import Foundation

/// Day-of-week aligned to Apple's "Lundi = first" convention, with the short
/// labels the onboarding chips and the Today week bars use.
nonisolated public enum Weekday: Int, CaseIterable, Codable, Sendable, Identifiable {
    case monday = 1
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    public var id: Int { rawValue }

    /// The day's initial in `locale` — « L », « M » in French, « M », « T » in
    /// English (issue #587).
    public func shortLabel(locale: Locale = .app) -> String {
        calendar(locale).veryShortStandaloneWeekdaySymbols[calendarWeekday - 1]
    }

    public var shortLabel: String { shortLabel() }

    /// The day's name in `locale`, as written mid-sentence: « mardi » in
    /// French, « Tuesday » in English.
    public func fullName(locale: Locale = .app) -> String {
        calendar(locale).weekdaySymbols[calendarWeekday - 1]
    }

    public var fullName: String { fullName() }

    private func calendar(_ locale: Locale) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar
    }

    /// Default "weekday" set used at onboarding (Mon → Fri).
    public static let workWeek: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    /// This day in `Calendar`'s numbering (1 = Sunday … 7 = Saturday), to feed
    /// `StreakCalculator` and `Calendar.component(.weekday:)`.
    public var calendarWeekday: Int { (rawValue % 7) + 1 }
}

nonisolated public extension Set where Element == Weekday {
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
