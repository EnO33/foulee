import SwiftUI

/// Orange flame card at the top of the Stats screen — mirrors the JSX
/// "SÉRIE ACTUELLE" hero.
struct StreakHeroCard: View {
    var currentStreak: Int
    var bestStreak: Int

    private var remainingToRecord: Int {
        max(bestStreak - currentStreak, 0)
    }

    private var barCount: Int {
        max(bestStreak, 14)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                flameIcon
                heroText
            }
            progressBars
        }
        .padding(20)
        .fouleeGlass(cornerRadius: 26)
    }

    private var flameIcon: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(FouleeColor.streakGradient)
            .frame(width: 76, height: 76)
            .overlay {
                Image(systemName: FouleeIcon.flame)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color(hex: 0xFF6B00).opacity(0.35), radius: 24, x: 0, y: 12)
    }

    private var heroText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SÉRIE ACTUELLE")
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(currentStreak)")
                    .font(FouleeFont.numeric(size: 38))
                Text("jours d'affilée")
                    .font(FouleeFont.callout)
                    .foregroundStyle(.secondary)
            }
            recordHint
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var recordHint: some View {
        if bestStreak == 0 {
            Text("Aucun record pour l'instant — c'est ta chance.")
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
        } else if remainingToRecord == 0 {
            HStack(spacing: 4) {
                Image(systemName: FouleeIcon.sparkle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FouleeColor.success)
                Text("Tu tiens ton record : \(bestStreak) jours")
                    .font(FouleeFont.footnote.weight(.medium))
                    .foregroundStyle(FouleeColor.success)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: FouleeIcon.arrowUp)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FouleeColor.success)
                Text("\(remainingToRecord) vers ton record (\(bestStreak))")
                    .font(FouleeFont.footnote.weight(.medium))
                    .foregroundStyle(FouleeColor.success)
            }
        }
    }

    private var progressBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(index < currentStreak
                        ? AnyShapeStyle(FouleeColor.accentGradient)
                        : AnyShapeStyle(Color.gray.opacity(0.15)))
                    .frame(height: 6)
            }
        }
    }
}
