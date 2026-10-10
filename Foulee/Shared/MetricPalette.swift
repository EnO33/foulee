import SwiftUI

/// The colour each daily metric is drawn in (issues #366, #372): steps purple
/// like the home's outer ring, minutes green like its inner one, distance
/// blue, calories orange.
///
/// SwiftUI-only so the watch compiles it too, like `ActivityPalette`: the same
/// figure must not change colour between the wrist and the phone. The values
/// are the brand's (`FouleeColor`), spelled out because the watch has no
/// design system.
enum MetricPalette {
    static let steps = Color(.sRGB, red: 191 / 255, green: 90 / 255, blue: 242 / 255)
    static let minutes = Color(.sRGB, red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let distance = Color(.sRGB, red: 10 / 255, green: 132 / 255, blue: 255 / 255)
    static let calories = Color(.sRGB, red: 255 / 255, green: 159 / 255, blue: 10 / 255)
}
