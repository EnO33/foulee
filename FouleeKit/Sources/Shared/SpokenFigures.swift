import Foundation

// Figures as VoiceOver says them (issue #600), shared by the watch, its
// complications and the iPhone's widgets (issue #601). The written forms are read symbol by symbol: « 0,9 / 2 L »
// as « 0,9 barre oblique 2 L », « 12 j » as « 12 j », « bpm » letter by letter.

/// « 0,9 litre sur 2 » — the water drunk against the day's goal.
nonisolated public func spokenHydrationText(intakeML: Int, goalML: Int, locale: Locale = .app) -> String {
    kitText("\(litres(intakeML, locale: locale)) litre sur \(litres(goalML, locale: locale))", locale: locale)
}

/// « Série de 12 jours ».
nonisolated public func spokenStreakText(days: Int, locale: Locale = .app) -> String {
    kitText("Série de \(days) jours", locale: locale)
}

/// « 128 battements par minute », or « Fréquence cardiaque indisponible »
/// before the first reading — a bare « — » is read « tiret ».
nonisolated public func spokenHeartRateText(_ beatsPerMinute: Int?, locale: Locale = .app) -> String {
    guard let beatsPerMinute else { return kitText("Fréquence cardiaque indisponible", locale: locale) }
    return kitText("\(beatsPerMinute) battements par minute", locale: locale)
}

/// « 250 millilitres » — a glass on the widgets' « J'ai bu » button
/// (issue #601), whose « +250 » is read « plus 250 ».
nonisolated public func spokenMillilitresText(_ millilitres: Int, locale: Locale = .app) -> String {
    Measurement(value: Double(millilitres), unit: UnitVolume.milliliters)
        .formatted(.measurement(width: .wide, usage: .asProvided).locale(locale))
}

/// « 8 240 pas sur 10 000 pas, 32 minutes sur 30 minutes » — the day's two
/// goals, which the iPhone's Today widget draws as bare rings (issue #601);
/// without `goals`, « 8 240 pas, 32 minutes ».
nonisolated public func spokenDayText(
    steps: Int,
    minutes: Int,
    goals: (steps: Int, minutes: Int)? = nil,
    locale: Locale = .app
) -> String {
    let figures = [(WalkMetric.steps, steps, goals?.steps), (WalkMetric.minutes, minutes, goals?.minutes)]
    return figures.map { metric, value, goal in
        goal.map { metric.spokenText(Double(value), goal: Double($0), locale: locale) }
            ?? metric.spokenText(Double(value), locale: locale)
    }
    .joined(separator: ", ")
}

/// « Objectif de 30 minutes » — the session's goal, which the Live Activity
/// draws as a ring around a bare percentage (issue #601).
nonisolated public func spokenGoalText(minutes: Int, locale: Locale = .app) -> String {
    kitText("Objectif de \(spokenDurationText(minutes: minutes, locale: locale))", locale: locale)
}
