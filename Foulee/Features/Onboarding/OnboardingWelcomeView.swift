import SwiftUI

/// First onboarding screen — brand logo + tagline + 3 value bullets +
/// "Commencer" CTA. Foulée is local-only (HealthKit + on-device
/// preferences), so there's no account step.
struct OnboardingWelcomeView: View {
    var onContinue: () -> Void

    private let bullets: [(icon: String, text: String)] = [
        // Neutral wording *and* a neutral glyph, because the very next screen
        // asks marche / course / les deux (#221, #222): promising "une marche
        // du midi" here and then offering the choice reads as if the answer
        // were already decided — and as if the app only worked at lunchtime.
        (FouleeIcon.mixedCardio, "Une sortie par jour ouvré"),
        (FouleeIcon.target, "Un objectif simple, pas un score"),
        // Neutral on purpose: Garmin (via Santé) works here too, and promising
        // an Apple Watch feature to someone who doesn't own one is a dead end.
        (FouleeIcon.watch, "Détection auto via ta montre")
    ]

    /// Centred when it fits, scrolling when it does not — the same shape as
    /// the three steps after it, with the button pinned below.
    ///
    /// It used to be one fixed column with a 76 pt top margin. On an iPhone SE
    /// the column ran a few points taller than the screen, and SwiftUI made
    /// up the difference by squeezing the texts onto one line each:
    /// « Bouge un peu,… », « Un objectif simple, pas un… ». A scroll view gives
    /// the texts all the height they ask for, so nothing is ever truncated —
    /// at any screen size or text size.
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)
                        appIcon
                        heading
                        featureCard
                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            footer
                .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    private var appIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(FouleeColor.accentGradient)
                .frame(width: 110, height: 110)
                .shadow(color: FouleeColor.accentMid.opacity(0.45), radius: 30, x: 0, y: 18)
                .rotationEffect(.degrees(-2))
            Image(systemName: FouleeIcon.sparkle)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var heading: some View {
        VStack(spacing: 8) {
            Text("Foulée")
                .kerning(-1)
                .scaledSystemFont(size: 40, weight: .heavy)
            Text("Bouge un peu,\nchaque jour.")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
    }

    private var featureCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(bullets.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FouleeColor.accentMid.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: entry.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(FouleeColor.accentMid)
                        }
                    // Wraps rather than truncates: on an iPhone SE « Un
                    // objectif simple, pas un score » is wider than the row,
                    // and without this the row kept it on one line, cut.
                    Text(entry.text)
                        .font(FouleeFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
            }
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 22)
        .padding(.top, 32)
    }

    private var footer: some View {
        PrimaryButton(title: "Commencer", systemIcon: nil, action: onContinue)
    }
}
