import Foundation
import Testing

/// The watch speaks English on a wrist set to English (issue #588).
///
/// Looked up in the app's own catalog rather than through a screen: the tests
/// run in French, and a missing table would only show on a device.
@Suite("Watch text")
struct WatchTextTests {
    private let french = Locale(identifier: "fr_FR")
    private let american = Locale(identifier: "en_US")

    private func text(_ resource: LocalizedStringResource, in locale: Locale) -> String {
        String(localized: LocalizedStringResource(resource.defaultValue, locale: locale, bundle: .main))
    }

    /// What `Locale.app` looks for: without it, figures and the kit's words
    /// would stay French beside English screens.
    @Test("The app ships an English table")
    func englishTable() {
        #expect(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en") != nil)
    }

    @Test("A label reads in the locale's language")
    func language() {
        #expect(text("Terminer", in: french) == "Terminer")
        #expect(text("Terminer", in: american) == "Finish")
        #expect(text("J'ai bu", in: american) == "Had a glass")
    }

    @Test("A streak picks its plural form in each language")
    func plurals() {
        #expect(text("Série de \(1) jours", in: french) == "Série de 1 jour")
        #expect(text("Série de \(12) jours", in: french) == "Série de 12 jours")
        #expect(text("Série de \(1) jours", in: american) == "1-day streak")
    }

    @Test("Arguments keep their place in English")
    func arguments() {
        #expect(text("Kilomètre \(3) en \("05:42")", in: american) == "Kilometer 3 in 05:42")
    }
}
