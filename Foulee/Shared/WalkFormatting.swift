import Foundation

extension TimeInterval {
    /// Elapsed walk time as `mm:ss`, promoting to `h:mm:ss` once the walk
    /// passes the hour. Shared by the iPhone + Watch active-walk and recap
    /// screens and the Live Activity so they all read identically.
    var walkClockText: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}

extension TimeInterval {
    /// This duration spent covering `km`, as a pace — « 6'10"/km » (issue
    /// #276).
    ///
    /// Nothing new is measured: a leg already carries its distance and its two
    /// dates, and pace is the division of one by the other. It is here rather
    /// than on the segment so the watch and the phone would state a pace the
    /// same way, the way they already agree on `walkClockText`.
    ///
    /// `nil` rather than a number below 50 m. A leg can be as short as 15 s
    /// (`WatchWorkoutStore.minimumLegDuration`), and over twenty paces the
    /// division amplifies a GPS-less distance estimate into a figure that looks
    /// precise and is not. Absent says « too short to say »; « 3'02"/km » on a
    /// stroll says something false.
    func paceText(overKm km: Double) -> String? {
        guard km >= 0.05, self > 0 else { return nil }
        let secondsPerKm = self / km
        // A pace this slow is a pause someone forgot to end, not a pace.
        guard secondsPerKm < 99 * 60 else { return nil }
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return String(format: "%d'%02d\"/km", minutes, seconds)
    }
}

extension Double {
    /// A km distance with a French decimal comma and no unit, e.g. `1,23`.
    func kmValue(fractionDigits: Int = 2) -> String {
        decimalComma(fractionDigits: fractionDigits)
    }

    /// A km distance with a French decimal comma and the `km` unit, e.g.
    /// `1,23 km`. `fractionDigits` defaults to 2; live screens that update
    /// every second pass `1` to keep the trailing digit calm.
    func kmText(fractionDigits: Int = 2) -> String {
        "\(kmValue(fractionDigits: fractionDigits)) km"
    }
}
