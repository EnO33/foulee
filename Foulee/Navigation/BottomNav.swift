import SwiftUI

/// 3-tab floating glass pill that sits over the content (`today`, `stats`,
/// `settings`). The active tab gets the accent gradient and a glow.
enum BottomNavTab: String, CaseIterable, Identifiable {
    case today
    case stats
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Auj."
        case .stats: "Stats"
        case .settings: "Réglages"
        }
    }

    var systemIcon: String {
        switch self {
        case .today: FouleeIcon.walk
        case .stats: FouleeIcon.calendar
        case .settings: FouleeIcon.settings
        }
    }
}

struct BottomNav: View {
    @Binding var active: BottomNavTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(BottomNavTab.allCases) { tab in
                Button {
                    active = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.systemIcon)
                            .font(.system(size: 20))
                        Text(tab.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(active == tab ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        Capsule()
                            .fill(FouleeColor.accentGradient)
                            .opacity(active == tab ? 1 : 0)
                    )
                    .shadow(
                        color: FouleeColor.accentMid.opacity(active == tab ? 0.4 : 0),
                        radius: 12, x: 0, y: 4
                    )
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .fouleeGlass(cornerRadius: 999, strong: true)
    }
}
