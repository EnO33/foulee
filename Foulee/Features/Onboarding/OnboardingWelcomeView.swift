import SwiftUI

/// First onboarding screen — brand logo + tagline + 3 value bullets +
/// "Commencer" CTA. Foulée is local-only (HealthKit + on-device
/// preferences), so there's no account step.
struct OnboardingWelcomeView: View {
    var onContinue: () -> Void

    private let bullets: [(icon: String, text: String)] = [
        (FouleeIcon.walk, "Une marche du midi par jour ouvré"),
        (FouleeIcon.target, "Un objectif simple, pas un score"),
        (FouleeIcon.watch, "Détection auto via Apple Watch")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            appIcon
            heading
            featureCard
            Spacer()
            footer
        }
        .padding(.horizontal, 24)
        .padding(.top, 76)
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
                .font(.system(size: 40, weight: .heavy))
                .kerning(-1)
            Text("Bouge un peu,\nchaque midi.")
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
                    Text(entry.text)
                        .font(FouleeFont.body)
                    Spacer()
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
