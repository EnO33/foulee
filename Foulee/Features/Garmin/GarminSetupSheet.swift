import SwiftUI

/// "J'ai une montre Garmin" — how to let Garmin Connect write into Santé
/// (issue #185, corrected in #205, reordered in #210). Reachable from the
/// onboarding permissions step and from Réglages, since a user often connects
/// the watch after install.
///
/// The ordering is first-hand, not researched (05/08/2026, owner's iPhone,
/// Garmin Connect FR): the connection is started **in Garmin Connect**, and an
/// app that has never requested HealthKit access is simply absent from Santé →
/// Confidentialité → Apps. Leading with the Santé screen — as #206 did — thus
/// opened on a step that necessarily fails for a first-time user. Santé keeps
/// its place as the verify/repair path. Garmin has renamed that menu at least
/// twice ("3rd Party Apps" → "Connected Apps" → "Connect Apps"), so the labels
/// stay hedged; the path itself no longer is.
struct GarminSetupSheet: View {
    var onClose: () -> Void

    /// Garmin Connect FR, confirmed on device: the entry keeps its English name
    /// "Apple Health" inside the French app. Step 5 is iOS's own permission
    /// sheet, which Garmin triggers — the categories are Apple's wording.
    private let steps = [
        "Ouvre Garmin Connect, onglet « Plus ».",
        "Touche « Paramètres », puis « Applications connectées ».",
        "Touche « Apple Health » — l'entrée garde son nom anglais.",
        "Touche « Se connecter avec Apple Health ».",
        """
        Santé affiche sa fenêtre d'autorisation : active les catégories — Pas, Distance, \
        Entraînements, Fréquence cardiaque, Calories, et Eau si tu suis ton hydratation.
        """
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SheetBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    stepsCard
                    verifyCard
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
                par un serveur. La connexion se lance depuis Garmin Connect.
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

    /// Santé, demoted to verify/repair. Apple lists an app here as soon as it
    /// has *asked* for access, whatever the answer was — so absence is not a
    /// bug, it is the signal that the Garmin Connect step above never ran. That
    /// asymmetry is what misled the owner; it is spelled out rather than implied.
    private var verifyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vérifier ou réparer, côté Santé")
                .font(FouleeFont.headline)
            Text("""
                Santé → Résumé → ta photo en haut à droite → sous « Confidentialité », « Apps » → \
                « Connect ». Attention : l'entrée porte ce nom-là, donc elle est classée à la \
                lettre C, pas à G — c'est ce qui fait chercher en vain. Tu y retrouves les mêmes catégories, à cocher \
                ou décocher quand tu veux.
                """)
                .font(FouleeFont.footnote)
                .foregroundStyle(.secondary)
            Text("""
                Garmin Connect n'apparaît dans cette liste qu'une fois la connexion établie : une app \
                y entre quand elle a demandé l'accès, jamais avant. Donc pas dans la liste = la \
                connexion n'a jamais été faite, commence par Garmin Connect ci-dessus. Dans la liste = \
                tout se règle là, même si tu avais répondu « Ne pas autoriser ».
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
                    met en pause et ne reprend qu'à la synchro suivante. Compte quelques minutes \
                    (environ 5) avant de voir tes données dans Foulée — ce n'est pas instantané. \
                    Journée en retard ? Ouvre Garmin Connect et laisse-la ouverte un moment.
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
            Les libellés de Garmin Connect changent d'une version à l'autre — « Applications \
            connectées » s'est déjà appelé « Applications tierces ». Le chemin, lui, ne bouge pas : \
            les paramètres, puis les applications connectées.
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
            // Without this the hit area is the glyphs only, not the row.
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}

#Preview("Light") { GarminSetupSheet(onClose: {}).preferredColorScheme(.light) }
#Preview("Dark") { GarminSetupSheet(onClose: {}).preferredColorScheme(.dark) }
