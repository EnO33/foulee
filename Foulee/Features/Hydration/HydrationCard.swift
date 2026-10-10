import SwiftUI

/// Home hydration card (issues #329, #353): a row of glasses filling up toward
/// the goal, where the day stands against its rhythm, and the one-tap
/// « J'ai bu ». No manual amount entry — one tap = one glass.
struct HydrationCard: View {
    let intakeML: Int
    let goalML: Int
    let glassML: Int
    let pace: HydrationPace
    var onDrink: () -> Void

    static let water = Color.teal

    private var fills: [Double] {
        HydrationMath.glassFills(intakeML: intakeML, goalML: goalML, glassML: glassML)
    }

    private var reached: Bool { pace == .reached }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(Self.water)
                Text("Hydratation").font(FouleeFont.headline)
                Spacer()
                Text("\(litres(intakeML)) / \(litres(goalML)) L")
                    .scaledNumericFont(size: 16, weight: .semibold)
                    .foregroundStyle(reached ? Self.water : .secondary)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 6) {
                ForEach(Array(fills.enumerated()), id: \.offset) { _, fill in
                    HydrationGlass(fill: fill)
                        .frame(maxWidth: 26)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 34)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hydratation")
            .accessibilityValue("\(litres(intakeML)) litre sur \(litres(goalML))")

            HStack {
                Label(pace.text, systemImage: pace.systemImage)
                    .font(FouleeFont.footnote.weight(reached ? .semibold : .regular))
                    .foregroundStyle(reached ? Self.water : .secondary)
                    .labelStyle(.titleAndIcon)
                    .contentTransition(.opacity)
                Spacer(minLength: 8)
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
        .animation(.spring(duration: 0.6, bounce: 0.25), value: intakeML)
        .sensoryFeedback(.increase, trigger: intakeML)
    }
}

/// One glass of the row: a tapered outline, water rising inside it.
struct HydrationGlass: View {
    let fill: Double

    var body: some View {
        ZStack(alignment: .bottom) {
            GlassShape()
                .fill(HydrationCard.water.opacity(0.1))
            Rectangle()
                .fill(HydrationCard.water.gradient)
                .scaleEffect(x: 1, y: fill, anchor: .bottom)
                .mask(GlassShape())
            GlassShape()
                .stroke(HydrationCard.water.opacity(fill > 0 ? 0.7 : 0.35), lineWidth: 1.5)
        }
        .aspectRatio(0.75, contentMode: .fit)
    }
}

/// A drinking glass, wider at the rim than at the base.
private struct GlassShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.14
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 16) {
        HydrationCard(intakeML: 875, goalML: 2_000, glassML: 250, pace: .behind(glasses: 2)) {}
        HydrationCard(intakeML: 2_100, goalML: 2_000, glassML: 250, pace: .reached) {}
    }
    .padding()
    .background(Color.black)
}
