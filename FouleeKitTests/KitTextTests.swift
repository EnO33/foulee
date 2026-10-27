import Foundation
import Testing
@testable import FouleeKit

/// The kit's own text follows the language of the app showing it (issue #587).
@Suite("Kit text")
struct KitTextTests {
    private let french = Locale(identifier: "fr_FR")
    private let american = Locale(identifier: "en_US")

    @Test("A label reads in the locale's language, not the device's")
    func language() {
        #expect(kitText("Marche", locale: french) == "Marche")
        #expect(kitText("Marche", locale: american) == "Walk")
    }

    @Test("A count picks its plural form in each language")
    func plurals() {
        #expect(kitText("\(1) minutes", locale: french) == "1 minute")
        #expect(kitText("\(12) minutes", locale: french) == "12 minutes")
        #expect(kitText("\(1) minutes", locale: american) == "1 minute")
        #expect(kitText("\(120) mètres de montée", locale: american) == "120 meters up")
    }

    @Test("Arguments keep their place when the sentence reorders them")
    func arguments() {
        #expect(kitText("Ta plus longue \("walk") depuis 6 mois", locale: american) == "Your longest walk in 6 months")
    }
}
