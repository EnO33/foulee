import SwiftUI

/// A goal or rhythm set with a slider (issue #395): its value printed large
/// above the track, and the same pair handed to VoiceOver — a bare `Slider`
/// is announced as a percentage, « 45 % », which says nothing.
///
/// Works on whole numbers: every slider in Réglages stores an `Int`, so the
/// `Double` bridge lives here once instead of in each call site.
struct SettingsSlider: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int
    var tint: Color
    /// The value as the screen says it — « 20 min », « 6 000 pas ».
    var format: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(format(value))
                .scaledNumericFont(size: 20, weight: .semibold)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            ) {
                Text(title)
            }
            .tint(tint)
            .accessibilityValue(format(value))
        }
        // One light tick per notch, as the system pickers do.
        .sensoryFeedback(.selection, trigger: value)
    }
}
