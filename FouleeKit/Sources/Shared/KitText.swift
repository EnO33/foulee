import Foundation

/// `resource` from the kit's own catalog, in the language of the screens it
/// lands on (issue #587).
///
/// A literal passed here is extracted into `FouleeKit/Resources/Localizable.xcstrings`.
/// The kit is embedded in apps that do not all speak the same languages yet:
/// the lookup follows `Locale.app`, the language of the app showing the text,
/// rather than the device's — an English iPhone with a French-only watch would
/// otherwise get « Walk » among French words on the wrist.
nonisolated public func kitText(_ resource: LocalizedStringResource, locale: Locale = .app) -> String {
    // Rebuilt rather than edited: the bundle of a resource is fixed. Its value
    // carries the key the literal was extracted under, and the arguments.
    String(localized: LocalizedStringResource(resource.defaultValue, locale: locale, bundle: .atURL(Bundle.kit.bundleURL)))
}

nonisolated extension Bundle {
    /// FouleeKit's framework bundle, where its catalog is compiled.
    static let kit = Bundle(for: KitBundleToken.self)
}

private final class KitBundleToken {}
