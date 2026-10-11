import SwiftUI

/// The pages the Réglages home drills into (issue #393), one per theme. Each
/// carries the glyph and tint its home row draws.
enum SettingsPage: Hashable {
    case goals
    case schedule
    case hydration
    case notifications
    case appearance
    case about

    var title: String {
        switch self {
        case .goals: "Objectifs"
        case .schedule: "Planning"
        case .hydration: "Hydratation"
        case .notifications: "Notifications"
        case .appearance: "Apparence"
        case .about: "À propos"
        }
    }

    var icon: String {
        switch self {
        case .goals: FouleeIcon.target
        case .schedule: "calendar"
        case .hydration: "drop.fill"
        case .notifications: FouleeIcon.bell
        case .appearance: "circle.lefthalf.filled"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .goals: FouleeColor.success
        case .schedule: FouleeColor.accentSecondary
        case .hydration: FouleeColor.water
        case .notifications: FouleeColor.danger
        case .appearance: FouleeColor.accentMid
        case .about: .gray
        }
    }
}

/// The page behind a `SettingsPage`, pushed on the Réglages stack.
struct SettingsPageView: View {
    let page: SettingsPage
    @Bindable var preferences: UserPreferences
    let permission: NotificationPermissionStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        // No background: the stack sits on the sheet's `SheetBackground`,
        // as the Bilan's pushed detail does.
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .goals: SettingsGoalsPage(preferences: preferences)
        case .schedule: SettingsSchedulePage(preferences: preferences)
        case .hydration: GlassSection { HydrationSettingsContent(preferences: preferences) }
        case .notifications: SettingsNotificationsPage(preferences: preferences, store: permission)
        case .appearance: SettingsAppearancePage(preferences: preferences)
        case .about: SettingsAboutPage()
        }
    }
}
