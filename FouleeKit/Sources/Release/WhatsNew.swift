import Foundation

/// A notable version's « Nouveautés » (issue #621): what the app shows once,
/// at the first opening after the update. A version is notable when the app's
/// `WhatsNew.json` has an entry for it; the others show nothing.
nonisolated public struct WhatsNewRelease: Decodable, Equatable, Identifiable, Sendable {
    /// The marketing version, « 1.59 » or « 1.59.0 ».
    public var version: String
    public var id: String { version }
    public var items: [WhatsNewItem]

    public init(version: String, items: [WhatsNewItem]) {
        self.version = version
        self.items = items
    }

    /// The releases of a `WhatsNew.json` file, in any order.
    public static func decode(_ data: Data) throws -> [WhatsNewRelease] {
        try JSONDecoder().decode([WhatsNewRelease].self, from: data)
    }

    /// The release to show, running `current` after `lastSeen`: the newest one
    /// above `lastSeen` and up to `current`, if any.
    ///
    /// `lastSeen` is `nil` on an install from before this screen existed: every
    /// release up to `current` is new to it. A new install never gets here,
    /// the onboarding records its version as seen.
    public static func toShow(in releases: [WhatsNewRelease], current: String, lastSeen: String?) -> WhatsNewRelease? {
        releases
            .filter { release in
                compare(release.version, current) != .orderedDescending
                    && lastSeen.map { compare(release.version, $0) == .orderedDescending } ?? true
            }
            .max { compare($0.version, $1.version) == .orderedAscending }
    }

    /// Versions compared number by number, a missing one counting as zero:
    /// « 1.59 » is « 1.59.0 », and below « 1.60 ».
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = numbers(lhs)
        let right = numbers(rhs)
        for index in 0..<max(left.count, right.count) {
            let lhsPart = index < left.count ? left[index] : 0
            let rhsPart = index < right.count ? right[index] : 0
            if lhsPart != rhsPart { return lhsPart < rhsPart ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}

/// One change worth telling: an SF Symbol, a short title and a sentence, each
/// text in every language the app speaks.
nonisolated public struct WhatsNewItem: Decodable, Equatable, Sendable {
    public var icon: String
    /// The text by language code, « fr » and « en ».
    public var title: [String: String]
    public var text: [String: String]

    public init(icon: String, title: [String: String], text: [String: String]) {
        self.icon = icon
        self.title = title
        self.text = text
    }

    /// The title in `language`, French when it has none in that language.
    public func title(in language: String) -> String {
        Self.localized(title, in: language)
    }

    public func text(in language: String) -> String {
        Self.localized(text, in: language)
    }

    private static func localized(_ texts: [String: String], in language: String) -> String {
        texts[language] ?? texts["fr"] ?? ""
    }
}
