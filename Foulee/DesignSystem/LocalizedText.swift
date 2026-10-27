import Foundation

extension LocalizedStringResource {
    /// Text already in the screen's language — a figure, a name, a label the
    /// kit wrote — for a component that takes a key (issue #587). Its key, « %@ »,
    /// is marked as not to be translated in the catalog.
    static func verbatim(_ text: String) -> LocalizedStringResource {
        "\(text)"
    }
}
