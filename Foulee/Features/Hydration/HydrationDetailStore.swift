import Dependencies
import Foundation
import Observation

/// Loads the Hydratation screen (issue #355): today's glasses one by one, and
/// the last seven days. The intake itself stays `HydrationStore`'s, shared
/// with the home card; this one only adds what the screen alone shows.
@MainActor
@Observable
final class HydrationDetailStore {
    private(set) var samples: [WaterSample] = []
    private(set) var history: HydrationHistory?
    private(set) var lastError: String?

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    @ObservationIgnored
    @Dependency(\.date) private var date

    func load(goalML: Int) async {
        do {
            async let samples = healthKit.waterToday()
            async let series = healthKit.waterSeries(HydrationHistory.window)
            let (today, days) = try await (samples, series)
            self.samples = today
            history = HydrationHistory.make(series: days, goalML: goalML, now: date.now)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
