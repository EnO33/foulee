import SwiftUI

nonisolated enum ThemeMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: String(localized: "Clair")
        case .dark: String(localized: "Sombre")
        case .system: String(localized: "Système")
        }
    }

    /// `nil` means "follow the system" — matches `.preferredColorScheme`.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}
