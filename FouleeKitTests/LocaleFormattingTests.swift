import Foundation
import Testing
@testable import FouleeKit

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
        let locale = Locale.app(device: american, preferences: ["en-US", "de"])
        #expect(locale.language.languageCode == .french)
        #expect(locale.region == .unitedStates)
        #expect(Locale.app(device: french, preferences: ["fr-FR"]) == french)
    }
}
