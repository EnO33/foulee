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

extension Double {
    /// A km distance with a French decimal comma and no unit, e.g. `1,23`.
    func kmValue(fractionDigits: Int = 2) -> String {
        String(format: "%.\(fractionDigits)f", self)
            .replacingOccurrences(of: ".", with: ",")
    }

    /// A km distance with a French decimal comma and the `km` unit, e.g.
    /// `1,23 km`. `fractionDigits` defaults to 2; live screens that update
    /// every second pass `1` to keep the trailing digit calm.
    func kmText(fractionDigits: Int = 2) -> String {
        "\(kmValue(fractionDigits: fractionDigits)) km"
    }
}
