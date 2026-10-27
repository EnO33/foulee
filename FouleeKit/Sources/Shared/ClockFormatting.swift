import Foundation

nonisolated public extension Date {
    /// « 08:10 » — the wall-clock time every Foulée screen prints a session
    /// with, in the hours the device reads: « 8:10 AM » in the US (issue #586).
    var clockText: String { Self.clockFormatter.string(from: self) }

    private static let clockFormatter = DateFormatter(template: "jmm")
}

nonisolated public extension DateComponents {
    /// « 18:30 » for an hour-and-minute setting such as the outing window, or
    /// « — » when it carries neither.
    var clockText: String { clockText(with: Self.clockFormatter) }

    /// The same setting, in the hours `locale` reads — « 6:30 PM » in the US.
    func clockText(locale: Locale) -> String {
        clockText(with: Self.utcFormatter(locale: locale))
    }

    /// Laid on a day in UTC, so no time zone can move the hour it names.
    private func clockText(with formatter: DateFormatter) -> String {
        guard let hour, let minute,
              let date = Self.utc.date(bySettingHour: hour, minute: minute, second: 0, of: Self.utcDay)
        else { return "—" }
        return formatter.string(from: date)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private static let utcDay = Date(timeIntervalSinceReferenceDate: 0)

    private static let clockFormatter = utcFormatter(locale: .app)

    private static func utcFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter(template: "jmm", locale: locale)
        formatter.timeZone = .gmt
        return formatter
    }
}

nonisolated public extension Date {
    /// « mardi 27 octobre », « Tuesday, October 27 ».
    var dayText: String { Self.dayFormatter.string(from: self) }

    /// « mardi 27 oct. », « Tuesday, Oct 27 ».
    var shortDayText: String { Self.shortDayFormatter.string(from: self) }

    /// « M », « T » — the weekday's initial, for a calendar's column.
    var weekdayInitial: String { Self.weekdayInitialFormatter.string(from: self) }

    private static let dayFormatter = DateFormatter(template: "EEEEdMMMM")
    private static let shortDayFormatter = DateFormatter(template: "EEEEdMMM")
    private static let weekdayInitialFormatter = DateFormatter(template: "EEEEE")
}
