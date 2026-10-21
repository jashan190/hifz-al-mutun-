import SwiftUI

/// Stand-in for the app's Theme (UIKit only), so Subject builds on the Mac.
enum Theme {
    static func subjectAccent(_ subject: Subject) -> Color { .clear }
}
