import Foundation

nonisolated public extension Locale {
    /// The locale every Foulée figure and date is written in (issue #586): the
    /// device's region and preferences — separators, 12 or 24 hours — in the
    /// language the screens are actually shown in.
    ///
    /// Not `Locale.current` alone: on a device set to a language Foulée does
    /// not speak, the screens fall back to French, and « Wednesday » or
    /// « 4,218 pas » beside them would read as two apps.
    static let app = app(device: .current, preferences: Locale.preferredLanguages)

    /// The languages Foulée's screens are written in, source first. One more
    /// here when a catalog gains one.
    internal static let screenLanguages = ["fr"]

    /// `device` speaking the screen language the user prefers among
    /// `screenLanguages` — French when none of theirs is one.
    internal static func app(device: Locale, preferences: [String]) -> Locale {
        let language = Bundle.preferredLocalizations(from: screenLanguages, forPreferences: preferences).first
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
