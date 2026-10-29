import SwiftUI

/// A Réglages switch: its title, and one line saying what it changes.
struct SettingsToggle: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    @Binding var isOn: Bool

    init(_ title: LocalizedStringResource, detail: LocalizedStringResource, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FouleeFont.headline)
                Text(detail)
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(FouleeColor.success)
    }
}
