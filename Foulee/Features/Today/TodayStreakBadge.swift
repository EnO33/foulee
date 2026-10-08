import SwiftUI

/// The streak, as a flame and a number beside the profile button.
///
/// It had a whole card to itself, beside the weather. The number is the part
/// read every day; the record and the calendar are one tap away, behind this
/// same badge.
///
/// **No capsule behind it.** With one, the badge was wide enough on an iPhone
/// SE to push « Aujourd'hui » onto two lines.
struct TodayStreakBadge: View {
    var streak: Int
    var bestStreak: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: FouleeIcon.flame)
                    .scaledSystemFont(size: 20, weight: .semibold)
                    .foregroundStyle(FouleeColor.warning)
                Text("\(streak)")
                    .scaledNumericFont(size: 22, weight: .semibold)
            }
        }
        .buttonStyle(.pressable)
        // No `.accessibilityElement(children: .ignore)`: on a `Button` it swaps
        // the button's own element for a plain one, and VoiceOver — like the
        // App Store capture querying `buttons` — no longer finds a button.
        .accessibilityLabel("Série")
        .accessibilityValue("\(streak) jours, record \(bestStreak) jours")
        .accessibilityHint("Voir ta série")
        // Same handle the old streak card carried: the App Store capture
        // (issue #235) waits on it as the home's sentinel, then taps it.
        .accessibilityIdentifier(TodayAccessibility.streakCard)
    }
}
