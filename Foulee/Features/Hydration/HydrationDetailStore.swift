import Dependencies
import Foundation
import Observation

/// Loads the Hydratation screen (issue #355): today's glasses one by one, and
/// the last seven days. The intake itself stays `HydrationStore`'s, shared
/// with the home card; this one only adds what the screen alone shows.
@MainActor
@Observable
final class HydrationDetailStore {
    /// Today's glasses, newest first: the one just drunk is the one looked
    /// for (issue #361).
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
            self.samples = today.sorted { $0.date > $1.date }
            history = HydrationHistory.make(series: days, goalML: goalML, now: date.now)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
