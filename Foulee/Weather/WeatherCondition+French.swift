import Foundation
import WeatherKit

/// Labels + walk-friendly advice, in the screens' language (issue #587), for
/// the handful of `WeatherCondition` cases the user will realistically see at
/// midday in metropolitan France.
/// Falls back to a long-dash for exotic ones (volcanic ash, hot, …).
nonisolated enum WeatherSummary {
    static func describe(
        condition: WeatherCondition,
        temperatureCelsius: Double
    ) -> (label: String, advice: String) {
        switch condition {
        case .clear, .mostlyClear:
            return (String(localized: "Ensoleillé"), temperatureAdvice(temperatureCelsius))
        case .partlyCloudy, .mostlyCloudy:
            return (String(localized: "Partiellement nuageux"), temperatureAdvice(temperatureCelsius))
        case .cloudy:
            return (String(localized: "Nuageux"), temperatureAdvice(temperatureCelsius))
        case .rain, .heavyRain, .drizzle, .freezingRain, .sunShowers:
            return (String(localized: "Pluie"), String(localized: "prends ton parapluie"))
        case .snow, .heavySnow, .blowingSnow, .flurries, .wintryMix, .sunFlurries:
            return (String(localized: "Neige"), String(localized: "couvre-toi"))
        case .thunderstorms, .strongStorms, .isolatedThunderstorms, .scatteredThunderstorms:
            return (String(localized: "Orage"), String(localized: "reste à l'abri"))
        case .windy, .breezy, .blowingDust:
            return (String(localized: "Venteux"), String(localized: "habille-toi en couches"))
        case .foggy, .haze, .smoky:
            return (String(localized: "Brouillard"), String(localized: "visibilité réduite"))
        case .hot:
            return (String(localized: "Chaud"), String(localized: "chapeau + eau"))
        case .frigid:
            return (String(localized: "Glacial"), String(localized: "couvre-toi"))
        default:
            return ("—", "")
        }
    }

    private static func temperatureAdvice(_ celsius: Double) -> String {
        switch celsius {
        case ..<5: String(localized: "couvre-toi")
        case 5..<15: String(localized: "veste légère")
        case 15..<25: String(localized: "idéal")
        case 25..<30: String(localized: "T-shirt")
        default: String(localized: "chapeau + eau")
        }
    }
}
