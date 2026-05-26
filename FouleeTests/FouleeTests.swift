import Testing
@testable import Foulee

@Suite("Foulée smoke")
struct FouleeTests {
    @Test("App boots")
    func appBoots() {
        let app = FouleeApp()
        #expect(type(of: app) == FouleeApp.self)
    }
}
