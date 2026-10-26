import Foundation

/// Every web page the app links to (issue #396), in one place: fixed https
/// addresses on the site and the public repository, never built from user
/// input. What a user reads lives on getfoulee.app; the issue tracker and the
/// code stay on GitHub.
nonisolated enum AppLinks {
    private static let website = "https://getfoulee.app"
    private static let repository = "https://github.com/getfoulee/foulee"

    static let privacyPolicy = link("\(website)/confidentialite")
    static let support = link("\(website)/assistance")
    static let garminFAQ = link("\(website)/assistance/garmin")
    static let reportIssue = link("\(repository)/issues/new")
    static let sourceCode = link(repository)

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
