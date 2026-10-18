import SwiftUI

/// What the page can ask the reader to do. Passed down through the environment
/// so rows and words don't need to know about sessions or storage.
struct ReaderActions {
    /// A bayt number was tapped in Memorize: recite from that bayt.
    var startFromBayt: (Int) -> Void = { _ in }
    /// The blank of a hidden hemistich was tapped: show the next word.
    var revealNext: (Int) -> Void = { _ in }
    /// "Not a mistake" on a red word.
    var dismissMistake: (Int, Half, Int) -> Void = { _, _, _ in }
    /// "Not a mistake" on the words shown added after a word.
    var dismissAdded: (Int, Half, Int) -> Void = { _, _, _ in }
}

private struct ReaderActionsKey: EnvironmentKey {
    static let defaultValue = ReaderActions()
}

extension EnvironmentValues {
    var readerActions: ReaderActions {
        get { self[ReaderActionsKey.self] }
        set { self[ReaderActionsKey.self] = newValue }
    }
}
