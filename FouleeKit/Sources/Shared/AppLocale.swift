import Foundation

nonisolated public extension Locale {
    /// The locale every Foulée figure and date is written in (issue #586): the
    /// device's region and preferences — separators, 12 or 24 hours — in the
    /// language the screens are actually shown in.
    ///
    /// Not `Locale.current` alone: on a device set to a language Foulée does
    /// not speak, the screens fall back to French, and « Wednesday » or
    /// « 4,218 pas » beside them would read as two apps.
    static let app = app(
        device: .current,
        preferences: Locale.preferredLanguages,
        screenLanguages: Bundle.main.screenLanguages
    )

    /// `device` speaking the screen language the user prefers among
    /// `screenLanguages` — French when none of theirs is one.
    internal static func app(device: Locale, preferences: [String], screenLanguages: [String]) -> Locale {
        // Asked among no language at all, Foundation answers one anyway.
        let language = Bundle.preferredLocalizations(from: screenLanguages, forPreferences: preferences)
            .first { screenLanguages.contains($0) }
        return device.speaking(language ?? "fr")
    }

    /// This locale's region and preferences, in `language`.
    internal func speaking(_ language: String) -> Locale {
        var components = Locale.Components(locale: self)
        components.languageComponents.languageCode = Locale.Language(identifier: language).languageCode
        components.languageComponents.script = nil
        return Locale(components: components)
    }
}

nonisolated extension Bundle {
    /// The languages this bundle's screens are written in (issue #587): those
    /// with a compiled `Localizable` table. Each target gains one when its own
    /// catalog is translated — the iPhone app may speak English while the watch
    /// app it carries still speaks French only.
    ///
    /// Empty for a bundle without screens, such as a test runner.
    var screenLanguages: [String] {
        localizations.filter { language in
            ["strings", "stringsdict"].contains { kind in
                path(forResource: "Localizable", ofType: kind, inDirectory: nil, forLocalization: language) != nil
            }
        }
    }
}

nonisolated public extension DateFormatter {
    /// A formatter for the fields of `template` — `"EEEEdMMMM"` — ordered and
    /// punctuated the way `locale` writes them: « mercredi 25 février »,
    /// « Wednesday, February 25 ».
    convenience init(template: String, locale: Locale = .app) {
        self.init()
        self.locale = locale
        setLocalizedDateFormatFromTemplate(template)
    }
}
