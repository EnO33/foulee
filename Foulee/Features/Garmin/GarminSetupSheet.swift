import SwiftUI

/// "J'ai une montre Garmin" — how to let Garmin Connect write into Santé
/// (issue #185, corrected in #205). Reachable from the onboarding permissions
/// step and from Réglages, since a user often connects the watch after install.
///
/// The numbered steps stay inside the **Apple Health app**, which is also what
/// Garmin's own support page leads with: those labels are Apple's, stable and
/// verifiable. Garmin Connect's own menu has been renamed at least twice
/// ("3rd Party Apps" → "Connected Apps" → "Connect Apps") and Garmin's EN and
/// FR pages disagree about it today, so that path is a hedged hint for the one
/// case that needs it — never step 1, never a precondition.
struct GarminSetupSheet: View {
    var onClose: () -> Void

    /// Apple's own path (iPhone User Guide, iOS 26). The row is "Apps", a
    /// sibling of "Appareils" — not "Apps et services" (Garmin's stale label).
    private let steps = [
        "Ouvre l'app Santé, onglet Résumé.",
        "Touche ta photo ou tes initiales, en haut à droite.",
        "Sous « Confidentialité », touche « Apps ».",
        "Touche « Garmin Connect » (ou « Connect ») dans la liste.",
        "Active les catégories : Pas, Distance, Entraînements, Fréquence cardiaque, Calories — et Eau si tu suis ton hydratation."
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SheetBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    stepsCard
                    diagnosticCard
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
                Une seule chose à obtenir : que Garmin Connect ait le droit d'écrire dans Santé. \
                Foulée y lit ensuite tes données comme celles d'une Apple Watch — rien ne passe \
                par un serveur. Ça se règle dans l'app Santé.
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

    /// The branch point that keeps this guide honest: Apple lists an app under
    /// Santé → Apps as soon as it has *asked* for access, whatever the answer
    /// was. Present therefore means everything is repairable in Santé alone;
    /// absent is the only case that needs Garmin Connect — and that is exactly
    /// where the menu labels are unreliable, hence the hedging.
    private var diagnosticCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Garmin Connect n'est pas dans la liste ?")
                .font(FouleeFont.headline)
            Text("""
                Une app y figure dès qu'elle a demandé l'accès à Santé, même si tu avais répondu \
                « Ne pas autoriser ». Si tu la vois, tout se répare là, sans toucher à Garmin Connect.
                """)
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
            Text("""
                Absente, c'est qu'elle n'a jamais demandé : ouvre Garmin Connect et lance la connexion \
                à Apple Santé depuis la section des applications connectées — le libellé varie selon \
                les versions (« Applications connectées », « Applications tierces »…) et l'entrée peut \
                ne s'afficher que tant que la connexion n'est pas faite. Reprends ensuite à l'étape 1.
                """)
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
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
                title: "Deux semaines d'historique",
                detail: """
                    À l'activation, Santé importe tes données Garmin des deux semaines précédentes. \
                    Plus ancien que ça, ton historique ne remonte pas.
                    """
            )
            caveat(
                icon: "arrow.triangle.2.circlepath",
                title: "Garmin Connect doit être ouverte",
                detail: """
                    Le transfert vers Santé n'a lieu que quand l'app est au premier plan. Fermée, il se \
                    met en pause et ne reprend qu'à la synchro suivante. Journée en retard dans Foulée ? \
                    Ouvre Garmin Connect.
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
        Text("""
            Les menus de Garmin Connect changent d'une version à l'autre — ceux de l'app Santé, non. \
            C'est pour ça que le réglage se fait d'abord côté Santé.
            """)
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
