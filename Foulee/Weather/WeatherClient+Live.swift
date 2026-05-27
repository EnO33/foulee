@preconcurrency import CoreLocation
import Foundation
import WeatherKit

extension WeatherClient {
    /// Real WeatherKit-backed implementation. Asks for the hourly forecast
    /// and picks the entry closest to today's local 12:00.
    static let liveValue: WeatherClient = WeatherClient(
        middayForecast: { coordinate in
            let location = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            let weather = try await WeatherService.shared.weather(for: location)
            let target = middayDate()
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

private func middayDate(now: Date = .now, calendar: Calendar = .current) -> Date {
    let components = calendar.dateComponents([.year, .month, .day], from: now)
    var midday = components
    midday.hour = 12
    midday.minute = 0
    midday.second = 0
    return calendar.date(from: midday) ?? now
}
