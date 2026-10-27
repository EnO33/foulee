import FouleeKit
import Foundation

/// Every web page the app links to (issue #396), in one place: fixed https
/// addresses on the site and the public repository, never built from user
/// input. What a user reads lives on getfoulee.app; the issue tracker and the
/// code stay on GitHub.
nonisolated enum AppLinks {
    private static let website = "https://getfoulee.app"
    private static let repository = "https://github.com/getfoulee/foulee"

    static let privacyPolicy = page(.privacyPolicy)
    static let support = page(.support)
    static let garminFAQ = page(.garminFAQ)
    static let reportIssue = link("\(repository)/issues/new")
    static let sourceCode = link(repository)

    /// A page of the site that exists in each language the app speaks.
    enum Page {
        case privacyPolicy, support, garminFAQ
    }

    /// `page` in the language the screens are shown in (issue #593): French at
    /// the root of the site, every other language on its English pages, under
    /// `/en`.
    static func page(_ page: Page, locale: Locale = .app) -> URL {
        guard locale.language.languageCode != .french else {
            switch page {
            case .privacyPolicy: return link("\(website)/confidentialite")
            case .support: return link("\(website)/assistance")
            case .garminFAQ: return link("\(website)/assistance/garmin")
            }
        }
        switch page {
        case .privacyPolicy: return link("\(website)/en/privacy")
        case .support: return link("\(website)/en/support")
        case .garminFAQ: return link("\(website)/en/support/garmin")
        }
    }

    /// The literals above are constants: a malformed one is a programming
    /// error, caught by `AppLinksTests` long before a user taps it.
    private static func link(_ string: String) -> URL {
        guard let url = URL(string: string) else { preconditionFailure("Invalid app link: \(string)") }
        return url
    }
}

/// The running build as the user reports it: « 1.52 (123) ».
nonisolated enum AppVersion {
    static var current: String {
        text(
            version: shortVersion,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    /// The App Store version alone, « 1.52 ».
    static var marketing: String {
        shortVersion ?? "0"
    }

    private static var shortVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static func text(version: String?, build: String?) -> String {
        let version = version ?? "0"
        guard let build, !build.isEmpty, build != version else { return version }
        return "\(version) (\(build))"
    }
}
