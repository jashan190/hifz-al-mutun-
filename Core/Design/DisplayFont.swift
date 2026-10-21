import SwiftUI
import UIKit

/// Title / body fonts for the library and covers. Titles are Aref Ruqaa
/// (calligraphic); body text is Amiri. Both are bundled and registered by
/// `PageFont.registerBundledFonts()`. Falls back to the serif system font.
enum DisplayFont {
    static func title(size: CGFloat) -> Font {
        PageFont.registerBundledFonts()
        return UIFont(name: "Aref Ruqaa", size: size) != nil
            ? .custom("Aref Ruqaa", fixedSize: size)
            : .system(size: size, design: .serif)
    }

    static func body(size: CGFloat) -> Font {
        PageFont.registerBundledFonts()
        return UIFont(name: "Amiri", size: size) != nil
            ? .custom("Amiri", fixedSize: size)
            : .system(size: size, design: .serif)
    }
}
