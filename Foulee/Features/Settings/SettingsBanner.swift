import SwiftUI

/// A warning with the one button that acts on it, at the top of a Réglages
/// page: notifications cut in iOS (issue #394), what Santé never tells
/// (issue #611).
struct SettingsBanner: View {
    let message: LocalizedStringResource
    let icon: String
    let action: LocalizedStringResource
    let perform: () -> Void

    var body: some View {
        GlassSection {
            Label {
                Text(message).font(FouleeFont.callout)
            } icon: {
                Image(systemName: icon).foregroundStyle(FouleeColor.warning)
            }
            Button(action: perform) {
                Text(action)
                    .font(FouleeFont.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(FouleeColor.accentMid.opacity(0.16), in: Capsule())
                    .foregroundStyle(FouleeColor.accentMid)
            }
            .buttonStyle(.pressable)
        }
    }
}
