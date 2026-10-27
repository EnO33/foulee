import Foundation
import Testing

/// Notifications, Siri phrases and the shared Bilan in English (issue #590).
///
/// Looked up in the app's own catalogs rather than through the code that uses
/// them: the tests run in French, and a missing entry would only show on a
/// device.
@Suite("Notification text")
struct NotificationTextTests {
    private let french = Locale(identifier: "fr_FR")
    private let american = Locale(identifier: "en_US")

    private func text(_ resource: LocalizedStringResource, in locale: Locale) -> String {
        String(localized: LocalizedStringResource(resource.defaultValue, locale: locale, bundle: .main))
    }

    @Test("Reminders and their actions read in English")
    func reminders() {
        #expect(text("C'est l'heure de bouger — ta sortie t'attend.", in: american) == "Time to move — your workout is waiting.")
        #expect(text("Ton récap de la semaine est prêt : minutes, pas et objectifs tenus.", in: american)
            == "Your weekly recap is ready: minutes, steps and goals met.")
        #expect(text("Rappelle-moi dans \(15) min", in: american) == "Remind me in 15 min")
    }

    @Test("The shared Bilan keeps its arguments in place and its plural in each language")
    func share() {
        #expect(text("\("My week") sur Foulée : \("8 h 30") d'activité, objectif tenu \(4) jours sur \(5).", in: american)
            == "My week on Foulée: 8 h 30 of activity, goal met on 4 of 5 days.")
        #expect(text("\("Ma semaine") sur Foulée : \("8 h 30") d'activité, objectif tenu \(1) jours sur \(5).", in: french)
            == "Ma semaine sur Foulée : 8 h 30 d'activité, objectif tenu 1 jour sur 5.")
        #expect(text("Objectif tenu \(1) jours sur \(5)", in: french) == "Objectif tenu 1 jour sur 5")
        #expect(text("Objectif tenu \(4) jours sur \(5)", in: american) == "Goal met on 4 of 5 days")
    }

    /// Siri reads its phrases from a table of their own; without an English
    /// one, an English iPhone offers the French phrases.
    @Test("The Siri phrases ship an English table")
    func shortcutPhrases() {
        #expect(Bundle.main.path(forResource: "AppShortcuts", ofType: "strings", inDirectory: nil, forLocalization: "en") != nil)
    }
}
