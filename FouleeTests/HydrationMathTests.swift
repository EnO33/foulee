import Testing
@testable import Foulee

@Suite struct HydrationMathTests {
    @Test func glassesRoundsToNearest() {
        #expect(HydrationMath.glasses(intakeML: 1_000, glassML: 250) == 4)
        #expect(HydrationMath.glasses(intakeML: 0, glassML: 250) == 0)
        // 600 / 250 = 2.4 → 2
        #expect(HydrationMath.glasses(intakeML: 600, glassML: 250) == 2)
        // 625 / 250 = 2.5 → 3 (round half up)
        #expect(HydrationMath.glasses(intakeML: 625, glassML: 250) == 3)
    }

    @Test func glassesGuardsZeroGlassSize() {
        #expect(HydrationMath.glasses(intakeML: 1_000, glassML: 0) == 0)
    }

    @Test func progressClampsToOne() {
        #expect(HydrationMath.progress(intakeML: 1_000, goalML: 2_000) == 0.5)
        #expect(HydrationMath.progress(intakeML: 3_000, goalML: 2_000) == 1)
        #expect(HydrationMath.progress(intakeML: 0, goalML: 2_000) == 0)
    }

    @Test func progressGuardsZeroGoal() {
        #expect(HydrationMath.progress(intakeML: 1_000, goalML: 0) == 0)
    }

    @Test func reachedGoal() {
        #expect(HydrationMath.reachedGoal(intakeML: 2_000, goalML: 2_000))
        #expect(HydrationMath.reachedGoal(intakeML: 2_500, goalML: 2_000))
        #expect(!HydrationMath.reachedGoal(intakeML: 1_999, goalML: 2_000))
        #expect(!HydrationMath.reachedGoal(intakeML: 500, goalML: 0))
    }
}
