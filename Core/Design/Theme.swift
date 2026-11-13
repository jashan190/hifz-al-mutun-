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
    static let ink = Color.dynamic(light: 0x12100D, dark: 0xF0ECE4)
    // UX.md asks for ≥4.5:1 on the page; its 45% gave 2.8:1 (light), so 62%.
    static let inkSecondary = ink.opacity(0.62)   // revealed hints, dimmed text
    static let numeral = ink.opacity(0.75)        // page / bayt / footnote numbers
    static let outline = ink.opacity(0.12)         // hidden hemistichs in Test

    // The app's identity colour — Madinah green. Used for app-level chrome (the
    // home masthead, settings, selected states). Green is now the one app colour;
    // subjects are told apart by icon, not hue.
    static let brand = Color.dynamic(light: 0x1E5B3A, dark: 0x5FB585)

    // Accents and marks
    static let accent = Color.dynamic(light: 0x1E5B3A, dark: 0x5FB585)   // Madinah green
    static let flag = Color.dynamic(light: 0xB4532A, dark: 0xE08A5F)
    static let error = Color.dynamic(light: 0xC62828, dark: 0xEF6B6B)
    // A deeper red for the outline drawn around the tapped review mistake, so the
    // edge reads darker than the light-red highlight fill it borders.
    static let errorEdge = Color.dynamic(light: 0x8E1B1B, dark: 0xC65454)
    // UX.md's light amber #B7860B is 3.1:1 on the page; darkened to 4.9:1.
    static let unsure = Color.dynamic(light: 0x8C6608, dark: 0xE0B341)
    // A mistake said right on going back: a bright yellow highlighter behind
    // ink text (yellow text would be unreadable on the page), set apart from
    // unsure's gold letters. In dark mode it is solid, under dark ink: a
    // see-through yellow over the dark page leaves light text under 4.5:1.
    static let fixedHighlight = Color(uiColor: UIColor { traits in
        UIColor(Color(hex: 0xFFD60A)).withAlphaComponent(traits.userInterfaceStyle == .dark ? 1 : 0.45)
    })

    /// The text on `fixedHighlight`: its own colour in light mode, dark ink
    /// (12:1 on the yellow) in dark mode.
    static func onFixed(_ color: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: 0x1D1B18))
                : UIColor(color).resolvedColor(with: traits)
        })
    }

    // Chrome — the original Madinah-green "covers" (header/footer). Solid, the
    // green first chosen for the app; kept deep in dark mode so cream text reads.
    static let chrome = Color.dynamic(light: 0x1E5B3A, dark: 0x15402A)
    static let onChrome = Color.dynamic(light: 0xF4EEDE, dark: 0xE8E2D2)     // cream on green
    static let onChromeDim = onChrome.opacity(0.65)
    static let chromeHairline = onChrome.opacity(0.22)

    /// The header/footer (and sidecar) bar colour. Madinah green is the app's one
    /// identity colour now — subjects are told apart by icon, not hue.
    static func subjectChrome(_ subject: Subject) -> Color { chrome }

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
    static let quran = Color.dynamic(light: 0x0C2E47, dark: 0x8AC6E8)
    static let rumuz = Color.dynamic(light: 0x6E1019, dark: 0xF28A8E)
    //  • sabz — whole bayts the edition prints in green (e.g. the naming bayt):
    //    the Madinah green, matching the bab headings.
    static let sabz = Color.dynamic(light: 0x0F3A23, dark: 0x74C79A)

    // One accent for every subject now: Madinah green. Subjects are distinguished
    // by their icon (`Subject.icon`), not colour.
    static func subjectAccent(_ subject: Subject) -> Color { accent }

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
