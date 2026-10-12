import SwiftUI
import CoreText
import UIKit

// The matn page is set in Amiri Quran (bundled) — a Quranic naskh that renders
// the ḍabṭ marks (small superscript letters, superscript alif, etc.). Falls back
// to plain Amiri, then the system font. Everything else uses the system font.
// We register the bundled fonts (lazily, once) and expose one place to get the
// page font and to measure a hemistich's width, so a page shares one size.

enum PageFont {
    // Preferred first; first one that's actually registered wins.
    private static let candidates = ["Amiri Quran", "Amiri"]

    private static var didRegister = false
    private(set) static var resolvedName: String? = nil

    /// Register every .ttf in the bundle. Safe to call repeatedly; runs once.
    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        resolvedName = candidates.first { UIFont(name: $0, size: 12) != nil }
    }

    /// SwiftUI font for the page at a fixed point size.
    static func font(size: CGFloat) -> Font {
        registerBundledFonts()
        return resolvedName.map { .custom($0, fixedSize: size) } ?? .system(size: size)
    }

    /// UIKit font used for width measurement; must match `font(size:)`.
    static func uiFont(size: CGFloat) -> UIFont {
        registerBundledFonts()
        return resolvedName.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size)
    }

    /// Rendered width of a single-line string at a given size.
    static func width(_ text: String, size: CGFloat) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: uiFont(size: size)]).width
    }
}
