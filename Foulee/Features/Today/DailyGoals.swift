import Foundation

/// Which of the day's two goals are met (issue #368) — the home's two rings.
/// Compared from one snapshot to the next, it tells the moment a ring closes,
/// which is what gets celebrated: the crossing, never the state.
struct DailyGoals: Equatable, Sendable {
    var steps: Bool
    var minutes: Bool

    init(steps: Bool, minutes: Bool) {
        self.steps = steps
        self.minutes = minutes
    }

    /// The minutes goal also counts as met once the outing is done, as the
    /// inner ring closes then (`TodayHeroCard`).
    init(_ snapshot: TodaySnapshot) {
        self.steps = snapshot.stepsGoal > 0 && snapshot.steps >= snapshot.stepsGoal
        self.minutes = snapshot.hasWalkedToday
            || (snapshot.minutesGoal > 0 && snapshot.minutes >= snapshot.minutesGoal)
    }

    /// Whether going from `old` to `self` closed a ring.
    func closesARing(since old: DailyGoals) -> Bool {
        (steps && !old.steps) || (minutes && !old.minutes)
    }
}
