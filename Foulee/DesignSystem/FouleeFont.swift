import SwiftUI

/// Type ramp matching the design's `.t-largetitle … .t-caption` classes.
/// Every token is text-style relative, so it tracks the user's Dynamic Type
/// setting; the weights mirror the original fixed-size design at the
/// default (Large) size.
enum FouleeFont {
    static let largeTitle = Font.system(.largeTitle, weight: .bold)
    static let title2 = Font.system(.title2, weight: .bold)
    static let title3 = Font.system(.title3, weight: .semibold)
    static let headline = Font.system(.headline, weight: .semibold)
    static let body = Font.system(.body, weight: .regular)
    static let callout = Font.system(.callout, weight: .regular)
    static let footnote = Font.system(.footnote, weight: .regular)
    static let caption = Font.system(.caption, weight: .regular)

    /// Rounded design with tabular digits — for big counters and timers.
    /// Frozen at `size`: shipping views must go through `scaledNumericFont`
    /// so the counter tracks Dynamic Type.
    static func numeric(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}
