import Testing
@testable import Foulee

@Suite struct WalkMetricTests {
    @Test func fractionDigitsPerMetric() {
        #expect(WalkMetric.distance.fractionDigits == 1)
        #expect(WalkMetric.steps.fractionDigits == 0)
        #expect(WalkMetric.minutes.fractionDigits == 0)
        #expect(WalkMetric.calories.fractionDigits == 0)
    }

    @Test func distanceFormatsWithOneDecimalComma() {
        #expect(WalkMetric.distance.formatted(4.2) == "4,2")
        #expect(WalkMetric.distance.formatted(12.0) == "12,0")
        #expect(WalkMetric.distance.formattedWithUnit(4.2) == "4,2 km")
    }

    @Test func wholeNumberMetricsHaveNoDecimalSeparator() {
        // steps/minutes/calories round to integers — never a decimal comma.
        #expect(WalkMetric.minutes.formatted(25) == "25")
        #expect(WalkMetric.calories.formatted(142.6) == "143")
        #expect(!WalkMetric.steps.formatted(5_391).contains(","))
        #expect(WalkMetric.steps.formattedWithUnit(25) == "25 pas")
    }

    /// Minutes are a duration once totalled (issue #366).
    @Test func minutesWithUnitReadAsADuration() {
        #expect(WalkMetric.minutes.formattedWithUnit(42) == "42 min")
        #expect(WalkMetric.minutes.formattedWithUnit(360) == "6 h")
        #expect(WalkMetric.minutes.formattedWithUnit(95.4) == "1 h 35")
    }
}
