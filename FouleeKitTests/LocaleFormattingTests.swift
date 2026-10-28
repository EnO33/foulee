import Foundation
import Testing
@testable import FouleeKit

/// What VoiceOver reads: the system puts a no-break space, narrow or not,
/// where it likes, and VoiceOver reads it as a space.
func plain(_ text: String?) -> String? {
    text?.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
}

/// Figures and dates follow the device's locale (issue #586). Every case names
/// its locale and its date, so none depends on the machine running it.
@Suite("Locale formatting")
struct LocaleFormattingTests {
    private let french = Locale(identifier: "fr_FR")
    private let american = Locale(identifier: "en_US")

    /// 20:05 on 27 October 2026, in UTC.
    private let evening = Date(timeIntervalSince1970: 1_793_131_500)

    private func utc(_ template: String, _ locale: Locale) -> DateFormatter {
        let formatter = DateFormatter(template: template, locale: locale)
        formatter.timeZone = .gmt
        return formatter
    }

    @Test("Thousands group as the locale groups them")
    func grouped() {
        #expect(4_218.groupedText(locale: french) == "4\u{202F}218")
        #expect(4_218.groupedText(locale: american) == "4,218")
    }

    @Test("Decimals take the locale's separator")
    func decimals() {
        #expect(1.5.decimalText(locale: french) == "1,5")
        #expect(1.5.decimalText(locale: american) == "1.5")
        #expect(1.234.kmText(locale: french) == "1,23 km")
        #expect(1.234.kmText(fractionDigits: 1, locale: american) == "1.2 km")
        #expect(litres(1_500, locale: american) == "1.5")
        #expect(WalkMetric.distance.formatted(4.2, locale: american) == "4.2")
        #expect(WalkMetric.steps.formatted(5_391, locale: american) == "5,391")
    }

    @Test("Durations read « 1 h 05 » in French, « 1 hr, 5 min » in English")
    func durations() {
        #expect(durationText(minutes: 45, locale: french) == "45 min")
        #expect(durationText(minutes: 65, locale: french) == "1 h 05")
        #expect(durationText(minutes: 360, locale: french) == "6 h")
        #expect(durationText(minutes: -3, locale: french) == "0 min")
        #expect(durationText(minutes: 45, locale: american) == "45 min")
        #expect(durationText(minutes: 65, locale: american) == "1 hr, 5 min")
        #expect(durationText(minutes: 360, locale: american) == "6 hr")
    }

    @Test("VoiceOver hears durations and paces in words, in the locale's")
    func spoken() {
        #expect(plain(spokenDurationText(seconds: 754, locale: french)) == "12 minutes et 34 secondes")
        #expect(plain(spokenDurationText(seconds: 3_900, locale: french)) == "1 heure et 5 minutes")
        #expect(plain(spokenDurationText(minutes: 45, locale: american)) == "45 minutes")
        #expect(plain(spokenDurationText(seconds: -3, locale: french)) == "0 seconde")
        #expect(plain(spokenPaceText(secondsPerKm: 330, locale: french)) == "5 minutes et 30 secondes par kilomètre")
        #expect(plain(spokenPaceText(secondsPerKm: 330, locale: american)) == "5 minutes, 30 seconds per kilometer")
    }

    @Test("VoiceOver hears a cadence and a day's figures with their units in words")
    func spokenUnits() {
        #expect(spokenCadenceText(steps: 330, over: 120, locale: french) == "165 pas par minute")
        #expect(spokenCadenceText(stepsPerSecond: 2.75, locale: american) == "165 steps per minute")
        #expect(spokenCadenceText(steps: 30, over: 5, locale: french) == nil)
        #expect(spokenCadenceText(stepsPerSecond: .nan, locale: french) == nil)
        #expect(plain(WalkMetric.steps.spokenText(8_240, locale: french)) == "8 240 pas")
        #expect(plain(WalkMetric.minutes.spokenText(65, locale: french)) == "1 heure et 5 minutes")
        #expect(plain(WalkMetric.distance.spokenText(4.2, locale: french)) == "4,2 kilomètres")
        #expect(plain(WalkMetric.distance.spokenText(4.2, locale: american)) == "4.2 kilometers")
        #expect(plain(WalkMetric.calories.spokenText(320.4, locale: french)) == "320 kilocalories")
        #expect(plain(WalkMetric.steps.spokenText(8_240, goal: 10_000, locale: french)) == "8 240 pas sur 10 000 pas")
        #expect(spokenHydrationText(intakeML: 900, goalML: 2_000, locale: french) == "0,9 litre sur 2,0")
        #expect(spokenStreakText(days: 1, locale: french) == "Série de 1 jour")
        #expect(spokenStreakText(days: 12, locale: french) == "Série de 12 jours")
        #expect(spokenStreakText(days: 1, locale: american) == "1-day streak")
        #expect(spokenHeartRateText(128, locale: american) == "128 beats per minute")
        #expect(spokenHeartRateText(nil, locale: french) == "Fréquence cardiaque indisponible")
        #expect(spokenMillilitresText(250, locale: french) == "250 millilitres")
        #expect(spokenMillilitresText(250, locale: american) == "250 milliliters")
        #expect(
            plain(spokenDayText(steps: 8_240, minutes: 32, goals: (10_000, 30), locale: french))
                == "8 240 pas sur 10 000 pas, 32 minutes sur 30 minutes"
        )
        #expect(plain(spokenDayText(steps: 8_240, minutes: 32, locale: french)) == "8 240 pas, 32 minutes")
        #expect(spokenGoalText(minutes: 30, locale: french) == "Objectif de 30 minutes")
        #expect(spokenGoalText(minutes: 30, locale: american) == "Goal: 30 minutes")
    }

    @Test("A setting's time reads in the locale's hours")
    func settingClock() {
        let window = DateComponents(hour: 18, minute: 30)
        #expect(window.clockText(locale: french) == "18:30")
        #expect(window.clockText(locale: american) == "6:30\u{202F}PM")
        #expect(DateComponents(hour: 18).clockText(locale: french) == "—")
        #expect(TimeOfDay(hour: 9, minute: 5).clockText == "09:05")
    }

    @Test("Days and months are named and ordered as the locale writes them")
    func dates() {
        #expect(utc("jmm", french).string(from: evening) == "20:05")
        #expect(utc("jmm", american).string(from: evening) == "8:05\u{202F}PM")
        #expect(utc("EEEEdMMMM", french).string(from: evening) == "mardi 27 octobre")
        #expect(utc("EEEEdMMMM", american).string(from: evening) == "Tuesday, October 27")
        #expect(utc("dMMM", french).string(from: evening) == "27 oct.")
        #expect(utc("dMMM", american).string(from: evening) == "Oct 27")
        #expect(utc("EEEEE", french).string(from: evening) == "M")
        #expect(utc("EEEEE", american).string(from: evening) == "T")
    }

    /// The screens fall back to French on a device whose language Foulée does
    /// not speak: its figures follow the screens, the region stays the device's.
    @Test("The app locale speaks the screens' language in the device's region")
    func appLocale() {
        let frenchInTheUS = Locale(identifier: "en_US").speaking("fr")
        #expect(frenchInTheUS.language.languageCode == .french)
        #expect(frenchInTheUS.region == .unitedStates)
        #expect(durationText(minutes: 65, locale: frenchInTheUS) == "1 h 05")
    }

    @Test("A language the screens do not speak falls back to French")
    func fallback() {
        let locale = Locale.app(device: american, preferences: ["en-US", "de"], screenLanguages: ["fr"])
        #expect(locale.language.languageCode == .french)
        #expect(locale.region == .unitedStates)
        #expect(Locale.app(device: french, preferences: ["fr-FR"], screenLanguages: ["fr", "en"]) == french)
        #expect(Locale.app(device: american, preferences: ["en-US"], screenLanguages: []).language.languageCode == .french)
    }

    /// The iPhone speaks English before the watch does (issue #587): each app
    /// reads its figures in the language its own catalog offers.
    @Test("English once the screens speak it, in the device's order of preference")
    func english() {
        let locale = Locale.app(device: american, preferences: ["en-US", "fr"], screenLanguages: ["fr", "en"])
        #expect(locale.language.languageCode == .english)
        #expect(locale == american)
        let secondChoice = Locale.app(device: american, preferences: ["de", "en"], screenLanguages: ["fr", "en"])
        #expect(secondChoice.language.languageCode == .english)
    }

    @Test("A bundle without a Localizable table has no screen language")
    func screenLanguages() {
        #expect(Bundle(for: LocaleToken.self).screenLanguages.isEmpty)
    }

    @Test("The source language counts once a translation ships")
    func sourceLanguage() {
        #expect(Bundle.screenLanguages(translated: ["en"], source: "fr") == ["fr", "en"])
        #expect(Bundle.screenLanguages(translated: ["fr", "en"], source: "fr") == ["fr", "en"])
        #expect(Bundle.screenLanguages(translated: [], source: "fr").isEmpty)
    }
}

private final class LocaleToken {}
