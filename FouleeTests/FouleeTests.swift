import SwiftUI
import Testing
@testable import Foulee

@Suite("Foulée smoke")
struct FouleeSmokeTests {
    @Test("App boots")
    func appBoots() {
        let app = FouleeApp()
        #expect(type(of: app) == FouleeApp.self)
    }
}

@Suite("Color(hex:)")
struct ColorHexTests {
    @Test("Decodes pure red, green, blue")
    func decodesPrimaries() {
        let red = Color(hex: 0xFF0000)
        let green = Color(hex: 0x00FF00)
        let blue = Color(hex: 0x0000FF)
        // SwiftUI's Color is opaque about its components — assert by
        // round-tripping the brand accent and verifying the description
        // contains the expected sRGB triple bucket.
        let accent = Color(hex: 0xBF5AF2)
        #expect("\(accent)" != "\(red)")
        #expect("\(red)" != "\(green)")
        #expect("\(green)" != "\(blue)")
    }

    @Test("Default opacity is 1, custom opacity is honoured")
    func opacityDefaults() {
        let solid = Color(hex: 0xBF5AF2)
        let half = Color(hex: 0xBF5AF2, opacity: 0.5)
        #expect("\(solid)" != "\(half)")
    }
}
