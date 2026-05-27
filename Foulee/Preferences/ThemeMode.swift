import SwiftUI

enum ThemeMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Clair"
        case .dark: "Sombre"
        case .system: "Système"
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
