import SwiftUI

/// "J'ai une montre Garmin" — how to switch Garmin Connect's Apple Health
/// export on (issue #185). Reachable from the onboarding permissions step and
/// from Réglages, since a user often connects the watch after the install.
///
/// The steps describe a third-party app: Garmin Connect renames and moves its
/// menus between versions, so the copy stays close to the wording it has used
/// for years and the sheet says out loud that labels may differ. Re-check
/// against the current Garmin Connect release before touching this file.
struct GarminSetupSheet: View {
    var onClose: () -> Void

    private let steps = [
        "Ouvre l'app Garmin Connect sur ton iPhone.",
        "Va dans Réglages, puis Santé Apple.",
        "Active Pas, Fréquence cardiaque, Entraînements, Calories et Distance — plus Eau si tu suis ton hydratation.",
        "Accepte la feuille d'autorisation qu'iOS affiche ensuite."
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SheetBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    stepsCard
                    caveatsCard
                    labelsNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            closeButton.padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: FouleeIcon.watch)
                .scaledSystemFont(size: 34, weight: .semibold)
                .foregroundStyle(FouleeColor.accentMid)
                .accessibilityHidden(true)
            Text("J'ai une montre Garmin")
                .font(FouleeFont.largeTitle)
            Text("""
                Garmin Connect écrit tes données dans Santé. Foulée les lit ensuite comme celles \
                d'une Apple Watch — rien ne passe par un serveur.
                """)
                .font(FouleeFont.body)
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 48)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(FouleeFont.headline)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(FouleeColor.accentGradient))
                        .accessibilityHidden(true)
                    Text(step)
                        .font(FouleeFont.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fouleeGlass(cornerRadius: 22)
    }

    /// The two honest caveats — both are Garmin behaviours Foulée can't fix,
    /// and knowing them up front avoids reading them as app bugs.
    private var caveatsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            caveat(
                icon: "clock.arrow.circlepath",
                title: "Pas de rattrapage",
                detail: "Seules les données postérieures à l'activation arrivent dans Santé. Ton historique Garmin, lui, ne remonte pas."
            )
            caveat(
                icon: "arrow.triangle.2.circlepath",
                title: "Synchro par rafales",
                detail: """
                    Garmin Connect pousse tes données quand tu ouvres l'app. \
                    Si ta journée semble en retard dans Foulée, ouvre Garmin Connect.
                    """
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fouleeGlass(cornerRadius: 22)
    }

    private func caveat(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .scaledSystemFont(size: 18, weight: .semibold)
                .foregroundStyle(FouleeColor.warning)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FouleeFont.headline)
                Text(detail)
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var labelsNote: some View {
        Text("Les noms des menus changent d'une version de Garmin Connect à l'autre : cherche « Santé Apple » dans les réglages de l'app.")
            .font(FouleeFont.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Fermer")
    }
}

/// Row that opens the guide — same wording in onboarding and in Réglages, so
/// the entry point reads the same wherever the user finds it.
struct GarminSetupLink: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: FouleeIcon.watch)
                    .scaledSystemFont(size: 18, weight: .semibold)
                    .foregroundStyle(FouleeColor.accentMid)
                VStack(alignment: .leading, spacing: 2) {
                    Text("J'ai une montre Garmin")
                        .font(FouleeFont.headline)
                        .foregroundStyle(.primary)
                    Text("Activer la synchro vers Santé")
                        .font(FouleeFont.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.pressable)
    }
}

#Preview("Light") { GarminSetupSheet(onClose: {}).preferredColorScheme(.light) }
#Preview("Dark") { GarminSetupSheet(onClose: {}).preferredColorScheme(.dark) }
