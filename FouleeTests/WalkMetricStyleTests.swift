import SwiftUI
import Testing
@testable import Foulee

/// A metric is drawn in the colour of its ring everywhere (issue #366).
@Suite("Metric colours")
struct WalkMetricStyleTests {
    @Test("Steps and minutes take the home ring's colours")
    func ringsColours() {
        // The outer ring is the accent gradient, centred on accentMid; the
        // inner one the activity gradient, centred on success.
        #expect(WalkMetric.steps.tint == FouleeColor.accentMid)
        #expect(WalkMetric.minutes.tint == FouleeColor.success)
    }

    @Test("Every metric has its own colour")
    func distinctColours() {
        let tints = WalkMetric.allCases.map(\.tint)
        #expect(Set(tints.map(\.description)).count == WalkMetric.allCases.count)
    }
}
