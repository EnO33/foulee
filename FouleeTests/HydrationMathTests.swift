import Testing
@testable import Foulee

@Suite struct HydrationMathTests {
    @Test func reachedGoal() {
        #expect(HydrationMath.reachedGoal(intakeML: 2_000, goalML: 2_000))
        #expect(HydrationMath.reachedGoal(intakeML: 2_500, goalML: 2_000))
        #expect(!HydrationMath.reachedGoal(intakeML: 1_999, goalML: 2_000))
        #expect(!HydrationMath.reachedGoal(intakeML: 500, goalML: 0))
    }

    // MARK: - Glass row (#353)

    @Test func glassRowHasOneGlassPerServing() {
        let fills = HydrationMath.glassFills(intakeML: 875, goalML: 2_000, glassML: 250)
        #expect(fills == [1, 1, 1, 0.5, 0, 0, 0, 0])
    }

    @Test func glassRowRoundsAnUnevenGoalUp() {
        // 2 L in 300 ml glasses: seven glasses sharing the goal.
        #expect(HydrationMath.glassFills(intakeML: 0, goalML: 2_000, glassML: 300).count == 7)
    }

    @Test func glassRowNeverOverflowsTheCard() {
        let fills = HydrationMath.glassFills(intakeML: 2_000, goalML: 4_000, glassML: 200)
        #expect(fills.count == HydrationMath.maxGlasses)
        #expect(fills == [1, 1, 1, 1, 1, 0, 0, 0, 0, 0])
    }

    @Test func glassRowPastTheGoalIsFull() {
        #expect(HydrationMath.glassFills(intakeML: 2_600, goalML: 2_000, glassML: 250).allSatisfy { $0 == 1 })
    }

    @Test func glassRowWithoutGoalIsEmpty() {
        #expect(HydrationMath.glassFills(intakeML: 500, goalML: 0, glassML: 250).isEmpty)
        #expect(HydrationMath.glassFills(intakeML: 500, goalML: 2_000, glassML: 0).isEmpty)
    }
}
