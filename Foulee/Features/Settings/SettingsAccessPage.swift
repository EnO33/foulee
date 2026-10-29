import FouleeKit
import SwiftUI

/// Autorisations (issue #611): every permission iOS refused, each with what
/// Foulée cannot do without it and the button that gives it back.
struct SettingsAccessPage: View {
    let store: AccessStore

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            if let refused = store.refused {
                if refused.isEmpty {
                    GlassSection {
                        Label {
                            Text("Foulée a tout ce qu'il lui faut.").font(FouleeFont.callout)
                        } icon: {
                            Image(systemName: FouleeIcon.check).foregroundStyle(FouleeColor.success)
                        }
                    }
                }
                ForEach(refused, id: \.self) { DegradedBanner(state: $0) }
            }
            // Always shown: HealthKit never says a read was refused, so no
            // state above can stand for it.
            SettingsBanner(
                message: "Santé ne dit jamais à Foulée ce que tu partages. Si un chiffre manque, vérifie l'accès de Foulée dans Santé.",
                icon: FouleeIcon.heart,
                action: "Ouvrir Santé"
            ) {
                openURL(AppLinks.health)
            }
        }
    }
}
