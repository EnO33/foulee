import Dependencies
import Foundation

/// WeatherKit façade. `middayForecast(at:)` returns the forecast for today
/// at 12:00 local time at the given coordinate, mapped to the same
/// `WeatherSnapshot` shape the Today card consumes.
struct WeatherClient: Sendable {
    var middayForecast: @Sendable (_ at: Coordinate) async throws -> WeatherSnapshot
}

extension WeatherClient: DependencyKey {
    static let previewValue = WeatherClient(
        middayForecast: { _ in
            WeatherSnapshot(temperatureCelsius: 21, condition: "Ensoleillé", advice: "idéal")
        }
    )

    static let testValue = WeatherClient(
        middayForecast: { _ in
            WeatherSnapshot(temperatureCelsius: 0, condition: "—", advice: "")
        }
    )
}

extension DependencyValues {
    var weather: WeatherClient {
        get { self[WeatherClient.self] }
        set { self[WeatherClient.self] = newValue }
    }
}
