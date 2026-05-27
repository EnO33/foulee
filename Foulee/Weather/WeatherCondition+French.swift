import Foundation
import WeatherKit

/// French labels + walk-friendly advice for the handful of `WeatherCondition`
/// cases the user will realistically see at midday in metropolitan France.
/// Falls back to a long-dash for exotic ones (volcanic ash, hot, …).
enum WeatherSummary {
    static func describe(
        condition: WeatherCondition,
        temperatureCelsius: Double
    ) -> (label: String, advice: String) {
        switch condition {
        case .clear, .mostlyClear:
            return ("Ensoleillé", temperatureAdvice(temperatureCelsius))
        case .partlyCloudy, .mostlyCloudy:
            return ("Partiellement nuageux", temperatureAdvice(temperatureCelsius))
        case .cloudy:
            return ("Nuageux", temperatureAdvice(temperatureCelsius))
        case .rain, .heavyRain, .drizzle, .freezingRain, .sunShowers:
            return ("Pluie", "prends ton parapluie")
        case .snow, .heavySnow, .blowingSnow, .flurries, .wintryMix, .sunFlurries:
            return ("Neige", "couvre-toi")
        case .thunderstorms, .strongStorms, .isolatedThunderstorms, .scatteredThunderstorms:
            return ("Orage", "reste à l'abri")
        case .windy, .breezy, .blowingDust:
            return ("Venteux", "habille-toi en couches")
        case .foggy, .haze, .smoky:
            return ("Brouillard", "visibilité réduite")
        case .hot:
            return ("Chaud", "chapeau + eau")
        case .frigid:
            return ("Glacial", "couvre-toi")
        default:
            return ("—", "")
        }
    }

    private static func temperatureAdvice(_ celsius: Double) -> String {
        switch celsius {
        case ..<5: "couvre-toi"
        case 5..<15: "veste légère"
        case 15..<25: "idéal"
        case 25..<30: "T-shirt"
        default: "chapeau + eau"
        }
    }
}
