import SwiftUI

// The user's appearance preference, persisted in UserDefaults via @AppStorage
// under the key "appearance". `system` follows the device.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Automatic"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }

    /// nil lets the system decide; otherwise forces light/dark.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
