import Dependencies
import Foundation

/// WeatherKit façade. `forecast(at:time:)` returns the forecast at the given
/// coordinate for the hour closest to `time`, mapped to the same
/// `WeatherSnapshot` shape the Today card consumes.
///
/// `time` is the start of the user's outing window. It used to be a fixed
/// 12:00 — fine while the reading sat in its own « Météo · 12 h » card, wrong
/// once it moved next to « Départ dans 3 h » on the hero, where it reads as the
/// weather *for the outing*.
struct WeatherClient: Sendable {
    var forecast: @Sendable (_ at: Coordinate, _ time: Date) async throws -> WeatherSnapshot
}

extension WeatherClient: DependencyKey {
    static let previewValue = WeatherClient(
        forecast: { _, _ in
            WeatherSnapshot(temperatureCelsius: 21, condition: "Ensoleillé", advice: "idéal")
        }
    )

    static let testValue = WeatherClient(
        forecast: { _, _ in
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
