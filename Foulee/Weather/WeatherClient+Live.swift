@preconcurrency import CoreLocation
import Foundation
import WeatherKit

extension WeatherClient {
    /// Real WeatherKit-backed implementation. Asks for the hourly forecast
    /// and picks the entry closest to `target`.
    static let liveValue: WeatherClient = WeatherClient(
        forecast: { coordinate, target in
            let location = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            let weather = try await WeatherService.shared.weather(for: location)
            let hour = weather.hourlyForecast.forecast.min { lhs, rhs in
                abs(lhs.date.timeIntervalSince(target)) < abs(rhs.date.timeIntervalSince(target))
            } ?? weather.hourlyForecast.forecast.first

            let temp = hour?.temperature.converted(to: .celsius).value
                ?? weather.currentWeather.temperature.converted(to: .celsius).value
            let condition = hour?.condition ?? weather.currentWeather.condition
            let summary = WeatherSummary.describe(
                condition: condition,
                temperatureCelsius: temp
            )
            return WeatherSnapshot(
                temperatureCelsius: Int(temp.rounded()),
                condition: summary.label,
                advice: summary.advice
            )
        }
    )
}
