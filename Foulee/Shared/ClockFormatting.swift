import Foundation

extension Date {
    /// « 08:10 » — the wall-clock time every Foulée screen prints a session
    /// with. French and 24-hour whatever the device's locale: the app speaks
    /// French only, and « 8:10 AM » next to « Marche et course » reads as two
    /// apps.
    var clockText: String { Self.clockFormatter.string(from: self) }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
