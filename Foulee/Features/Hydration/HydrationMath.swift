import Foundation

/// Pure hydration arithmetic — extracted so the card stays declarative and the
/// rounding rules are unit-tested.
enum HydrationMath {
    static func reachedGoal(intakeML: Int, goalML: Int) -> Bool {
        goalML > 0 && intakeML >= goalML
    }

    /// Most glasses the card draws in a row; past it each one stands for a
    /// larger share of the goal, so a 4 L goal never overflows the card.
    static let maxGlasses = 10

    /// How full each glass of the card's row is, `0...1` each (issue #353):
    /// as many glasses as the goal holds, rounded up and at most `maxGlasses`,
    /// sharing the goal evenly; the last one drunk may be partly filled. Empty
    /// when there is no goal to draw.
    static func glassFills(intakeML: Int, goalML: Int, glassML: Int) -> [Double] {
        guard goalML > 0, glassML > 0 else { return [] }
        let count = min(Int((Double(goalML) / Double(glassML)).rounded(.up)), maxGlasses)
        let share = Double(goalML) / Double(count)
        let filled = Double(intakeML) / share
        return (0..<count).map { min(max(filled - Double($0), 0), 1) }
    }
}
