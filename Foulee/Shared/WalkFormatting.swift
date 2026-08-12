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

/// « 5'25"/km » from a pace already in seconds per kilometre, rounded to
/// `step` seconds (issue #300).
///
/// Distinct from `paceText(overKm:)`, which divides a whole stretch and can
/// afford the second it lands on. This one states a *live* figure, so it is
/// quantised: the rounding is not a convenience, it is the screen declining to
/// claim a resolution the measurement does not have.
///
/// A free function like `litres`, because there is no natural receiver — the
/// argument is already the answer, only unformatted.
func paceText(secondsPerKm: TimeInterval, roundedTo step: TimeInterval) -> String {
    let rounded = Int((secondsPerKm / step).rounded() * step)
    return String(format: "%d'%02d\"/km", rounded / 60, rounded % 60)
}

/// « 95 pas/min » — steps per minute over `elapsed`, or `nil` when the stretch
/// is too short to divide (issue #302).
///
/// **Rounded to five.** Over a short stretch the step counter's own
/// quantisation is worth a dozen or so steps a minute on its own, so a figure
/// stated to the step would be showing that quantisation and calling it
/// cadence. Nothing under ten seconds is stated at all.
///
/// HealthKit has nothing to offer here: the only identifier carrying the word
/// is `cyclingCadence`. Dividing the step count is not a fallback — it is the
/// only road.
func cadenceText(steps: Int, over elapsed: TimeInterval) -> String? {
    guard elapsed >= 10, steps > 0 else { return nil }
    let perMinute = Double(steps) / elapsed * 60
    // A **non-breaking** space: « 165 » stranded at the end of a line with
    // « pas/min » on the next reads as badly as the « pa/s » of issue #261. The
    // line still wraps on a 40 mm — it just wraps before the number rather than
    // between the number and what it counts.
    return "\(Int((perMinute / 5).rounded()) * 5)\u{00A0}pas/min"
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
