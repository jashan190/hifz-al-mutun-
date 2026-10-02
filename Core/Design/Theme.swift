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
    static let ink = Color.dynamic(light: 0x1D1B18, dark: 0xE9E5DD)
    static let inkSecondary = ink.opacity(0.45)   // revealed hints, dimmed text
    static let numeral = ink.opacity(0.75)        // page / bayt / footnote numbers
    static let outline = ink.opacity(0.12)         // hidden hemistichs in Test

    // Accents and marks
    static let accent = Color.dynamic(light: 0x1E5B3A, dark: 0x5FB585)   // Madinah green
    static let flag = Color.dynamic(light: 0xB4532A, dark: 0xE08A5F)
    static let error = Color.dynamic(light: 0xC62828, dark: 0xEF6B6B)
    static let unsure = Color.dynamic(light: 0xB7860B, dark: 0xE0B341)

    // Chrome — the original Madinah-green "covers" (header/footer). Solid, the
    // green first chosen for the app; kept deep in dark mode so cream text reads.
    static let chrome = Color.dynamic(light: 0x1E5B3A, dark: 0x15402A)
    static let onChrome = Color.dynamic(light: 0xF4EEDE, dark: 0xE8E2D2)     // cream on green
    static let onChromeDim = onChrome.opacity(0.65)
    static let chromeHairline = onChrome.opacity(0.22)

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

    // Spacing — a 4-point grid; 16-point screen margins.
    static let margin: CGFloat = 16
    static let gridUnit: CGFloat = 4
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
