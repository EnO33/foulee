import SwiftUI

/// Home hydration card: today's intake vs goal (litres + glasses) and the
/// one-tap "J'ai bu" button. No manual amount entry — one tap = one glass.
struct HydrationCard: View {
    let intakeML: Int
    let goalML: Int
    let glassML: Int
    var onDrink: () -> Void

    private static let water = Color.teal

    private var progress: Double { HydrationMath.progress(intakeML: intakeML, goalML: goalML) }
    private var glasses: Int { HydrationMath.glasses(intakeML: intakeML, glassML: glassML) }
    private var reached: Bool { HydrationMath.reachedGoal(intakeML: intakeML, goalML: goalML) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Self.water)
                Text("Hydratation").font(FouleeFont.headline)
                Spacer()
                Text("\(litres(intakeML)) / \(litres(goalML)) L")
                    .font(FouleeFont.numeric(size: 16, weight: .semibold))
                    .foregroundStyle(reached ? Self.water : .secondary)
            }

            ProgressView(value: progress)
                .tint(Self.water)

            HStack {
                Label(
                    reached ? "Objectif atteint 🎉" : "\(glasses) verre\(glasses > 1 ? "s" : "")",
                    systemImage: reached ? "checkmark.circle.fill" : "cup.and.saucer.fill"
                )
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                Spacer()
                Button(action: onDrink) {
                    Label("J'ai bu", systemImage: "drop.fill")
                        .font(FouleeFont.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Self.water, in: Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("J'ai bu un verre")
            }
        }
        .padding(16)
        .fouleeGlass(cornerRadius: 24)
        .sensoryFeedback(.increase, trigger: intakeML)
    }

    /// Millilitres → "1,5" (one decimal, comma separator).
    private func litres(_ millilitres: Int) -> String {
        String(format: "%.1f", Double(millilitres) / 1_000)
            .replacingOccurrences(of: ".", with: ",")
    }
}

#Preview {
    VStack(spacing: 16) {
        HydrationCard(intakeML: 1_000, goalML: 2_000, glassML: 250) {}
        HydrationCard(intakeML: 2_100, goalML: 2_000, glassML: 250) {}
    }
    .padding()
    .background(Color.black)
}
