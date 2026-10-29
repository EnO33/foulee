import Foundation
import Testing
@testable import Foulee

/// Réglages › À propos (issue #396).
@Suite("App links")
struct AppLinksTests {
    @Test("What a user reads is https on the site", arguments: [
        AppLinks.privacyPolicy, AppLinks.support, AppLinks.garminFAQ,
        AppLinks.page(.privacyPolicy, locale: Locale(identifier: "en_US")),
        AppLinks.page(.support, locale: Locale(identifier: "en_US")),
        AppLinks.page(.garminFAQ, locale: Locale(identifier: "en_US"))
    ])
    func siteLinks(url: URL) {
        #expect(url.scheme == "https")
        #expect(url.host() == "getfoulee.app")
    }

    @Test("French pages sit at the site's root, every other language's under /en", arguments: [
        ("fr_FR", "/confidentialite", "/assistance", "/assistance/garmin"),
        ("fr_CA", "/confidentialite", "/assistance", "/assistance/garmin"),
        ("en_US", "/en/privacy", "/en/support", "/en/support/garmin"),
        ("en_GB", "/en/privacy", "/en/support", "/en/support/garmin"),
        ("de_DE", "/en/privacy", "/en/support", "/en/support/garmin")
    ])
    func pagesFollowTheLanguage(locale: String, privacy: String, support: String, garmin: String) {
        let locale = Locale(identifier: locale)
        #expect(AppLinks.page(.privacyPolicy, locale: locale).path() == privacy)
        #expect(AppLinks.page(.support, locale: locale).path() == support)
        #expect(AppLinks.page(.garminFAQ, locale: locale).path() == garmin)
    }

    @Test("The tracker and the code are https on the project's repository", arguments: [
        AppLinks.reportIssue, AppLinks.sourceCode
    ])
    func repositoryLinks(url: URL) {
        #expect(url.scheme == "https")
        #expect(url.host() == "github.com")
        #expect(url.path().hasPrefix("/getfoulee/foulee"))
    }

    @Test("A report's text rides in the new issue's body, every reserved character escaped")
    func reportIssueBody() throws {
        let body = "a+b & c=d #1\n```"
        let url = AppLinks.reportIssue(body: body)
        #expect(url.path() == AppLinks.reportIssue.path())
        let query = try #require(url.query(percentEncoded: true))
        #expect(!query.dropFirst("body=".count).contains(where: { "+&=# \n`".contains($0) }))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items == [URLQueryItem(name: "body", value: body)])
    }

    @Test("The version carries its build when there is one")
    func version() {
        #expect(AppVersion.text(version: "1.52", build: "123") == "1.52 (123)")
        #expect(AppVersion.text(version: "1.52", build: nil) == "1.52")
        #expect(AppVersion.text(version: "1.52", build: "1.52") == "1.52")
        #expect(AppVersion.text(version: nil, build: nil) == "0")
    }
}
