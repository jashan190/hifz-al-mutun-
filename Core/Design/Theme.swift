import SwiftUI
import UIKit

// Design tokens from UX.md. One set of colours with light / dark values that
// follow the system. No screen should hard-code a colour, font, or margin —
// everything comes from here.

extension Color {
    /// Build a Color from a 0xRRGGBB hex literal.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// A colour that resolves to `light` or `dark` based on the system scheme.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

enum Theme {
    // Surfaces and ink
    static let page = Color.dynamic(light: 0xFBF8F1, dark: 0x141413)
    // Soft manuscript cream used by the matn covers and the reader pages — a
    // warm off-white (less yellow than the old 0xF4EBD3).
    static let cover = Color.dynamic(light: 0xF8F4EA, dark: 0x262320)
    static let ink = Color.dynamic(light: 0x1D1B18, dark: 0xE9E5DD)
    // UX.md asks for ≥4.5:1 on the page; its 45% gave 2.8:1 (light), so 62%.
    static let inkSecondary = ink.opacity(0.62)   // revealed hints, dimmed text
    static let numeral = ink.opacity(0.75)        // page / bayt / footnote numbers
    static let outline = ink.opacity(0.12)         // hidden hemistichs in Test

    // The app's own identity colour — a warm charcoal/ink, deliberately NOT any
    // subject hue (red/yellow/green/blue), used for app-level chrome (the home
    // masthead, settings, etc.). Flips light⇄dark so it stays legible.
    static let brand = Color.dynamic(light: 0x2E2C27, dark: 0xDAD5C9)

    // Accents and marks
    static let accent = Color.dynamic(light: 0x1E5B3A, dark: 0x5FB585)   // Madinah green
    static let flag = Color.dynamic(light: 0xB4532A, dark: 0xE08A5F)
    static let error = Color.dynamic(light: 0xC62828, dark: 0xEF6B6B)
    // UX.md's light amber #B7860B is 3.1:1 on the page; darkened to 4.9:1.
    static let unsure = Color.dynamic(light: 0x8C6608, dark: 0xE0B341)

    // Chrome — the original Madinah-green "covers" (header/footer). Solid, the
    // green first chosen for the app; kept deep in dark mode so cream text reads.
    static let chrome = Color.dynamic(light: 0x1E5B3A, dark: 0x15402A)
    static let onChrome = Color.dynamic(light: 0xF4EEDE, dark: 0xE8E2D2)     // cream on green
    static let onChromeDim = onChrome.opacity(0.65)
    static let chromeHairline = onChrome.opacity(0.22)

    /// The header/footer (and sidecar) bar colour for a subject — a deep,
    /// saturated version that stays dark enough for cream (`onChrome`) text in
    /// both light and dark mode. Qur'ān keeps the original Madinah green.
    static func subjectChrome(_ subject: Subject) -> Color {
        switch subject {
        case .quran:   return chrome
        case .hadith:  return .dynamic(light: 0xB0302A, dark: 0x7C241E)
        case .seerah:  return .dynamic(light: 0x203C9E, dark: 0x172A6E)
        case .aqeedah: return .dynamic(light: 0x5A2E6B, dark: 0x3C1E49)
        case .arabic:  return .dynamic(light: 0x6B4A2A, dark: 0x48311C)
        case .fiqh:    return .dynamic(light: 0x0E7E77, dark: 0x09605A)
        }
    }

    // Raised surfaces (library cards, sheets) above the paper.
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x201F1C)

    // The two ink colours the printed matn uses besides black, for the Suwaid
    // edition's segments. Chosen to sit calmly on the cream page and to stay
    // clear of the green accent (#1E5B3A), the burnt-orange flag (#B4532A) and
    // the brighter signal-red error (#C62828):
    //  • quran — Quranic words (and, in a few chapters, letter lists / terms):
    //    a deep ocean blue, well away from the green.
    //  • rumuz — code letters, the separating wāw, reader names, emphasis: a deep
    //    carmine that reads as book-red ink, a touch deeper and cooler than the
    //    error red so the two don't look like the same colour.
    static let quran = Color.dynamic(light: 0x1A5A86, dark: 0x74B6DE)
    static let rumuz = Color.dynamic(light: 0xB02430, dark: 0xEE7E82)

    // Per-subject accent colours for the library shelves and covers. Saturated
    // on purpose so a subject is recognizable at a glance, even at cover size.
    // Dark values are lightened so titles read on the dark page.
    static func subjectAccent(_ subject: Subject) -> Color {
        switch subject {
        case .quran:   return accent                                   // Madinah green
        case .hadith:  return .dynamic(light: 0xC0362C, dark: 0xE87E76)
        case .seerah:  return .dynamic(light: 0x203C9E, dark: 0x7389E6)
        case .aqeedah: return .dynamic(light: 0x5A2E6B, dark: 0xB487C6)
        case .arabic:  return .dynamic(light: 0x6B4A2A, dark: 0xC59C6E)
        case .fiqh:    return .dynamic(light: 0x0E8E86, dark: 0x53C6BE)
        }
    }

    // 16-point screen margins.
    static let margin: CGFloat = 16
}

enum Numerals {
    private static let eastern: [Character] = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]

    /// Eastern Arabic numerals (default for the matn page per UX.md).
    static func eastern(_ value: Int) -> String {
        String(String(value).map { ch in
            ch.wholeNumberValue.map { eastern[$0] } ?? ch
        })
    }
}
