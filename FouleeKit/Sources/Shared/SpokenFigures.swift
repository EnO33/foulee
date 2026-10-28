import Foundation

// Figures as VoiceOver says them (issue #600), shared by the watch and its
// complications. The written forms are read symbol by symbol: « 0,9 / 2 L »
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
