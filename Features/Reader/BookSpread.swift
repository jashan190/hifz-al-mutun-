import SwiftUI
import UIKit

/// The open iPhone Duo held on its side reads like a book: two pages at a
/// time, in fixed pairs (1–2, 3–4, …), the odd page on the right. The title
/// page (0) stands alone. A spread is named by its first page.
enum BookSpread {
    /// The spread that holds `page`.
    static func first(of page: Int) -> Int { page <= 0 ? 0 : page - (page - 1) % 2 }

    /// Every spread of a document with pages 1…`count`, title page first.
    static func spreads(pageCount count: Int) -> [Int] { [0] + Array(stride(from: 1, through: max(0, count), by: 2)) }

    /// The pages a spread shows, right to left: one for the title page, else
    /// two (nil on the left past the last page).
    static func pages(of first: Int, pageCount count: Int) -> [Int?] {
        first == 0 ? [0] : [first, first + 1 <= count ? first + 1 : nil]
    }

    /// The open Duo's inner screen: the only iPhone screen regular in both
    /// directions (a Pro Max on its side is compact in height).
    static func isInnerScreen(phone: Bool, regularWidth: Bool, regularHeight: Bool) -> Bool {
        #if DEBUG
        // `-debugBookView YES`: treat any iPhone as the inner screen, to check
        // the layout without a Duo.
        if UserDefaults.standard.bool(forKey: "debugBookView") { return true }
        #endif
        return phone && regularWidth && regularHeight
    }

    static func isInnerScreen(_ traits: UITraitCollection) -> Bool {
        isInnerScreen(phone: traits.userInterfaceIdiom == .phone,
                      regularWidth: traits.horizontalSizeClass == .regular,
                      regularHeight: traits.verticalSizeClass == .regular)
    }
}

/// Lets the app turn to landscape only on the Duo's inner screen.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        guard let traits = window?.windowScene?.traitCollection, BookSpread.isInnerScreen(traits) else { return .portrait }
        return .allButUpsideDown
    }

    /// Asks again when the screen changes (the phone folded or opened), so a
    /// folded phone goes back to portrait.
    static func screenChanged() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        }
    }
}
