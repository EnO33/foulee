import Dependencies
import Foundation
import Testing
@testable import Foulee

/// The forecast is for the outing window, not for noon (issue #327).
///
/// It moved from its own « Météo · 12 h » card onto the hero, next to « Départ
/// dans 3 h » — where a noon reading for an 18:30 window would read as the
/// weather the user is about to go out in, and be wrong.
@Suite("Today weather follows the window")
@MainActor
struct TodayStoreWeatherTimeTests {
    /// Every hour the store asked the forecast for, in order.
    private final class AskedTimes: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Date] = []
        func append(_ date: Date) { lock.withLock { values.append(date) } }
        var all: [Date] { lock.withLock { values } }
    }

    private static let now = Date(timeIntervalSince1970: 1_716_897_600) // 2024-05-28 12:00 UTC

    private func hourAndMinute(_ date: Date) -> [Int] {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return [parts.hour ?? -1, parts.minute ?? -1]
    }

    @Test("Refresh asks for the window's start today, then again when the window moves")
    func forecastFollowsTheWindow() async throws {
        let asked = AskedTimes()
        let suiteName = "TodayStoreWeatherTimeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserPreferences(defaults: defaults)

        try await withDependencies {
            $0.date = .constant(Self.now)
            $0.healthKit = .previewValue
            $0.location = .previewValue
            $0.weather = WeatherClient(forecast: { _, time in
                asked.append(time)
                return WeatherSnapshot(temperatureCelsius: 18, condition: "Ensoleillé", advice: "idéal")
            })
        } operation: {
            let store = TodayStore()
            preferences.walkWindowStart = TimeOfDay(hour: 12, minute: 30)
            store.apply(preferences: preferences)
            await store.refresh()

            let first = try #require(asked.all.last)
            #expect(hourAndMinute(first) == [12, 30])
            #expect(Calendar.current.isDate(first, inSameDayAs: Self.now))

            preferences.walkWindowStart = TimeOfDay(hour: 18, minute: 30)
            store.apply(preferences: preferences)
            for _ in 0..<200 where hourAndMinute(asked.all.last ?? first) != [18, 30] {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(hourAndMinute(try #require(asked.all.last)) == [18, 30])
        }
    }
}
