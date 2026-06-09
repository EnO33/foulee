import Foundation

/// Pure hydration arithmetic — extracted so the card stays declarative and the
/// rounding rules are unit-tested.
enum HydrationMath {
    /// Number of glasses an intake represents, rounded to nearest.
    static func glasses(intakeML: Int, glassML: Int) -> Int {
        guard glassML > 0 else { return 0 }
        return Int((Double(intakeML) / Double(glassML)).rounded())
    }

    /// Progress toward the goal, clamped to 0…1.
    static func progress(intakeML: Int, goalML: Int) -> Double {
        guard goalML > 0 else { return 0 }
        return min(Double(intakeML) / Double(goalML), 1)
    }

    static func reachedGoal(intakeML: Int, goalML: Int) -> Bool {
        goalML > 0 && intakeML >= goalML
    }
}
