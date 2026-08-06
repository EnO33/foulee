import SwiftUI

/// One-stop visual gallery of the design system — pure SwiftUI previews,
/// not wired into the running app. Open this file in Xcode and tab through
/// `Light` / `Dark` previews to review any styling change.
///
/// Only referenced from `#Preview` (which Periphery can't see into), so the
/// whole file is retained via `retain_files` in `.periphery.yml` — that also
/// keeps the design-system pieces it showcases, like `SecondaryButton`.
struct DesignSystemGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                colors
                typography
                chips
                ring
                stats
                buttons
            }
            .padding(20)
        }
        .background(Wallpaper())
    }

    private var colors: some View {
        section("Couleurs") {
            HStack(spacing: 12) {
                swatch("Accent", FouleeColor.accentMid)
                swatch("Success", FouleeColor.success)
                swatch("Warning", FouleeColor.warning)
                swatch("Danger", FouleeColor.danger)
            }
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FouleeColor.accentGradient)
                .frame(height: 56)
        }
    }

    private var typography: some View {
        section("Typographie") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Large title").font(FouleeFont.largeTitle)
                Text("Title 2").font(FouleeFont.title2)
                Text("Headline").font(FouleeFont.headline)
                Text("Body — bouge un peu, chaque jour.").font(FouleeFont.body)
                Text("Footnote").font(FouleeFont.footnote).foregroundStyle(.secondary)
                Text("1 712").font(FouleeFont.numeric(size: 32))
            }
        }
    }

    private var chips: some View {
        section("Chips") {
            HStack(spacing: 8) {
                Chip(label: "Départ dans 18 min", systemIcon: FouleeIcon.timer,
                     tint: FouleeColor.accentMid,
                     fill: FouleeColor.accentMid.opacity(0.16))
                Chip(label: "Terminée", systemIcon: FouleeIcon.check,
                     tint: FouleeColor.success,
                     fill: FouleeColor.success.opacity(0.16))
            }
        }
    }

    private var ring: some View {
        section("Anneau de progression") {
            HStack(spacing: 20) {
                ProgressRing(progress: 0.42) {
                    VStack(spacing: 2) {
                        Image(systemName: FouleeIcon.mixedCardio)
                            .font(.title2)
                            .foregroundStyle(FouleeColor.accentMid)
                        Text("1 342").font(FouleeFont.numeric(size: 20))
                        Text("pas").font(FouleeFont.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 132, height: 132)

                ProgressRing(progress: 1) {
                    Image(systemName: FouleeIcon.check)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(FouleeColor.accentMid)
                }
                .frame(width: 132, height: 132)
            }
        }
    }

    private var stats: some View {
        section("Stat blocks") {
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 18) {
                StatBlock(systemIcon: FouleeIcon.footsteps, label: "Pas",
                          value: "4 218", sub: "/ 6 000", tint: FouleeColor.accentMid)
                StatBlock(systemIcon: FouleeIcon.timer, label: "Minutes",
                          value: "24", sub: "/ 20", tint: FouleeColor.accentSecondary)
                StatBlock(systemIcon: FouleeIcon.distance, label: "Distance",
                          value: "1,8 km", sub: nil, tint: Color(hex: 0x0A84FF))
                StatBlock(systemIcon: FouleeIcon.flame, label: "Calories",
                          value: "142", sub: "kcal", tint: FouleeColor.warning)
            }
            .padding(18)
            .fouleeGlass(cornerRadius: 24)
        }
    }

    private var buttons: some View {
        section("Boutons") {
            VStack(spacing: 12) {
                PrimaryButton(title: "Démarrer ta sortie",
                              systemIcon: FouleeIcon.play) {}
                SecondaryButton(title: "Voir le résumé",
                                systemIcon: FouleeIcon.sparkle) {}
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(FouleeFont.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            content()
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color)
                .frame(height: 56)
            Text(name).font(FouleeFont.caption)
        }
    }
}

#Preview("Light") {
    DesignSystemGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
}
