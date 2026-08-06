import SwiftUI

/// Pill-shaped CTA with the accent gradient — "Démarrer la séance",
/// "Continuer", "Terminer l'installation".
struct PrimaryButton: View {
    var title: String
    var systemIcon: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemIcon {
                    Image(systemName: systemIcon)
                }
                Text(title)
            }
            .font(FouleeFont.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(FouleeColor.accentGradient, in: Capsule())
            .shadow(color: FouleeColor.accentMid.opacity(0.35), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.pressable)
    }
}

/// Subtle gray pill for secondary actions next to the primary CTA. Part of the
/// button pair shown in `DesignSystemGallery`; kept as the design-system
/// counterpart to `PrimaryButton`.
struct SecondaryButton: View {
    var title: String
    var systemIcon: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemIcon {
                    Image(systemName: systemIcon)
                }
                Text(title)
            }
            .font(FouleeFont.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.gray.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.pressable)
    }
}

/// Tap-feedback scaling — used by every Foulée button.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}
