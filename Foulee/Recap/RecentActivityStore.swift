import Dependencies
import Foundation
import Observation

/// Loads the « 7 derniers jours » view (issue #348): the last seven days as a
/// recap — ring, verdict, comparison with the seven before — and their
/// outings, day by day.
@MainActor
@Observable
final class RecentActivityStore {
    private(set) var recap: Recap?
    private(set) var days: [OutingDay] = []
    private(set) var lastError: String?

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    @ObservationIgnored
    @Dependency(\.date) private var date

    func load(goalMinutes: Int, activeDays: Set<Weekday>) async {
        let now = date.now
        let period = RecapPeriod.lastDays(OutingDay.window, endingOn: now)
        do {
            let inputs = try await RecapStore.readInputs(
                from: healthKit,
                daysBack: RecapStore.daysBack(covering: [period], from: now)
            )
            recap = Recap.make(period: period, from: inputs, goalMinutes: goalMinutes, activeDays: activeDays)
            days = OutingDay.lastDays(from: inputs.workouts, now: now)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
