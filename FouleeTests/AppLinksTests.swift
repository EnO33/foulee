import Foundation
import Testing
@testable import Foulee

/// Réglages › À propos (issue #396).
@Suite("App links")
struct AppLinksTests {
    @Test("Every link is https on the project's repository", arguments: [
        AppLinks.privacyPolicy, AppLinks.garminFAQ, AppLinks.reportIssue, AppLinks.sourceCode
    ])
    func links(url: URL) {
        #expect(url.scheme == "https")
        #expect(url.host() == "github.com")
        #expect(url.path().hasPrefix("/EnO33/foulee"))
    }

    @Test("The version carries its build when there is one")
    func version() {
        #expect(AppVersion.text(version: "1.52", build: "123") == "1.52 (123)")
        #expect(AppVersion.text(version: "1.52", build: nil) == "1.52")
        #expect(AppVersion.text(version: "1.52", build: "1.52") == "1.52")
        #expect(AppVersion.text(version: nil, build: nil) == "0")
    }
}
