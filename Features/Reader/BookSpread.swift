import SwiftUI
import UIKit

/// The open iPhone Duo held on its side reads like a book: two pages at a time.
/// Like a printed muṣḥaf, the cover (page 0) shares the opening spread with
/// page 1 — cover on the right, the poem's first page on the left — then 2·3,
/// 4·5, … (even pages on the right throughout). A spread is named by its
/// right-hand page.
enum BookSpread {
    /// The spread that holds `page`.
    static func first(of page: Int) -> Int {
        if page <= 1 { return 1 }                 // cover (0) and page 1 share the opening spread
        return page % 2 == 0 ? page : page - 1    // 2·3 → 2, 4·5 → 4, …
    }

    /// Every spread of a document with pages 1…`count`: the cover+1 opening,
    /// then even-numbered recto pages.
    static func spreads(pageCount count: Int) -> [Int] {
        guard count >= 1 else { return [] }
        return [1] + Array(stride(from: 2, through: count, by: 2))
    }

    /// The pages a spread shows as [right, left] — RTL lays the first element on
    /// the right. The opening spread is cover (right) · page 1 (left); otherwise
    /// the recto page and its verso (nil on the left past the last page).
    static func pages(of first: Int, pageCount count: Int) -> [Int?] {
        if first == 1 { return [0, 1] }           // cover (right) · page 1 (left)
        return [first, first + 1 <= count ? first + 1 : nil]
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
