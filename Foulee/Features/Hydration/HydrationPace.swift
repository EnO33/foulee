import Foundation

/// Where today's intake stands against the hydration window (issue #353): the
/// goal spread evenly from the window's start to its end, compared with what
/// was drunk so far. Pure, so the card only has to say it.
enum HydrationPace: Equatable, Sendable {
    /// Before the window, nothing drunk yet: the day has not started.
    case notStarted(TimeOfDay)
    /// Within a glass of the expected intake.
    case onTrack
    /// At least a glass more than expected.
    case ahead
    /// This many whole glasses behind the expected intake.
    case behind(glasses: Int)
    /// The goal is met.
    case reached

    /// The hours the goal is spread over — the reminders' own window. Not a
    /// `ClosedRange`: nothing stops Réglages from ending it before it starts.
    struct Window: Equatable, Sendable {
        var start: TimeOfDay
        var end: TimeOfDay
    }

    static func evaluate(
        intakeML: Int,
        goalML: Int,
        glassML: Int,
        window: Window,
        now: Date,
        calendar: Calendar = .current
    ) -> HydrationPace {
        if HydrationMath.reachedGoal(intakeML: intakeML, goalML: goalML) { return .reached }
        let fraction = elapsedFraction(of: window, at: now, calendar: calendar)
        if fraction == 0, intakeML == 0 { return .notStarted(window.start) }
        guard glassML > 0 else { return .onTrack }
        let gap = Double(intakeML) - Double(goalML) * fraction
        let glasses = Int((abs(gap) / Double(glassML)).rounded(.down))
        guard glasses >= 1 else { return .onTrack }
        return gap > 0 ? .ahead : .behind(glasses: glasses)
    }

    /// Share of the window behind `now`, `0...1`. A window that ends where it
    /// starts, or before, counts as over once its start has passed.
    static func elapsedFraction(of window: Window, at now: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        let start = Double(window.start.rawMinutes)
        let end = Double(window.end.rawMinutes)
        guard end > start else { return minutes >= start ? 1 : 0 }
        return min(max((minutes - start) / (end - start), 0), 1)
    }

    /// What the card says.
    var text: String {
        switch self {
        case .notStarted(let start): "Ta journée d'hydratation commence à \(Self.clock(start))"
        case .onTrack: "Pile dans ton rythme"
        case .ahead: "En avance sur ton rythme"
        case .behind(let glasses): glasses == 1 ? "Un verre de retard" : "\(glasses) verres de retard"
        case .reached: "Objectif atteint"
        }
    }

    /// « 9 h », « 9 h 30 ».
    private static func clock(_ time: TimeOfDay) -> String {
        time.minute == 0 ? "\(time.hour) h" : String(format: "%d h %02d", time.hour, time.minute)
    }

    var systemImage: String {
        switch self {
        case .notStarted: "sunrise"
        case .onTrack: "checkmark.circle"
        case .ahead: "hare"
        case .behind: "clock.arrow.circlepath"
        case .reached: "checkmark.seal.fill"
        }
    }
}
