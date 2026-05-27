import Testing
import WeatherKit
@testable import Foulee

@Suite("WeatherSummary")
struct WeatherSummaryTests {
    @Test("Clear sky at 21°C reads as Ensoleillé · idéal")
    func clearMild() {
        let summary = WeatherSummary.describe(condition: .clear, temperatureCelsius: 21)
        #expect(summary.label == "Ensoleillé")
        #expect(summary.advice == "idéal")
    }

    @Test("Rain bypasses the temperature heuristic")
    func rainyAdvice() {
        let summary = WeatherSummary.describe(condition: .rain, temperatureCelsius: 18)
        #expect(summary.label == "Pluie")
        #expect(summary.advice == "prends ton parapluie")
    }

    @Test("Below freezing flips temperature advice to couvre-toi")
    func coldAdvice() {
        let summary = WeatherSummary.describe(condition: .partlyCloudy, temperatureCelsius: 2)
        #expect(summary.advice == "couvre-toi")
    }

    @Test("Heat advice kicks in above 30°C")
    func hotAdvice() {
        let summary = WeatherSummary.describe(condition: .clear, temperatureCelsius: 32)
        #expect(summary.advice == "chapeau + eau")
    }
}
