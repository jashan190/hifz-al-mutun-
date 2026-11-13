import SwiftUI
import UIKit

/// Where the iPhone Duo is in its fold, as far as the reader's chrome cares.
/// Resolved from the hardware (is it a foldable?), the size classes, and the
/// orientation. Everything that isn't a Duo is `.standard` and keeps the
/// original header + footer, untouched.
enum ReaderLayout: Equatable {
    /// Regular iPhone or iPad: header on top, footer on the bottom.
    case standard
    /// Duo folded — the cover screen. Single page, controls in a vertical rail.
    case duoCover
    /// Duo open on its side — the inner screen in landscape. Two-page spread,
    /// controls in a vertical rail.
    case duoSpread
    /// Duo open upright — the inner screen in portrait. Single page, controls on
    /// the bottom, verse column centred.
    case duoPortrait

    /// Two pages side by side.
    var showsTwoPages: Bool { self == .duoSpread }
    /// Controls live in a vertical rail on the trailing edge (else a bottom bar).
    var usesVerticalRail: Bool { self == .duoCover || self == .duoSpread }
    /// Any of the Duo layouts (header removed, chapter shown as a running head).
    var isDuo: Bool { self != .standard }

    static func resolve(foldable: Bool,
                        regularWidth: Bool,
                        regularHeight: Bool,
                        isLandscape: Bool) -> ReaderLayout {
        guard foldable else { return .standard }
        if regularWidth && regularHeight {       // the inner screen
            return isLandscape ? .duoSpread : .duoPortrait
        }
        return .duoCover                          // the cover screen
    }
}

/// Whether this hardware is a foldable iPhone (Duo). The cover screen looks like
/// a normal compact-width iPhone to size classes, so we fall back to the model
/// identifier — which works on the device and the simulator alike.
enum DuoDevice {
    static var isFoldable: Bool {
        #if DEBUG
        // `-debugBookView YES`: treat any iPhone as a Duo, to check the layout
        // without the hardware.
        if UserDefaults.standard.bool(forKey: "debugBookView") { return true }
        #endif
        return foldableModelPrefixes.contains { modelIdentifier.hasPrefix($0) }
    }

    /// Known foldable iPhone model identifiers (iPhone Duo is `iPhone19,4`).
    private static let foldableModelPrefixes = ["iPhone19,4"]

    static let modelIdentifier: String = {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return sim
        }
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }()
}
