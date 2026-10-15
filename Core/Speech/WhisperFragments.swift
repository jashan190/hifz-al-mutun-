import Foundation

/// Turns WhisperKit's streaming state into tracker fragments.
///
/// WhisperKit re-transcribes the audio since its last confirmed segment about
/// once a second. Older segments are confirmed (they won't change again);
/// the rest are its current guess. That maps onto the tracker's model:
/// - each newly confirmed segment → a final fragment (committed);
/// - the unconfirmed text → a volatile fragment, which replaces the previous
///   one (it always covers everything since the last confirmed segment).
struct WhisperFragments {
    private var confirmedCount = 0
    private var lastVolatile = ""

    /// Fragments for a new streaming state, given the text of every confirmed
    /// segment so far and of the unconfirmed ones.
    mutating func update(confirmed: [String], unconfirmed: [String]) -> [TranscriptFragment] {
        var out: [TranscriptFragment] = []
        if confirmed.count > confirmedCount {
            let text = Self.join(confirmed[confirmedCount...])
            confirmedCount = confirmed.count
            if !text.isEmpty { out.append(.init(text: text, isFinal: true)) }
            lastVolatile = ""   // a final supersedes the guess: resend it
        }
        let guess = Self.join(unconfirmed[...])
        if guess != lastVolatile {
            lastVolatile = guess
            if !guess.isEmpty { out.append(.init(text: guess, isFinal: false)) }
        }
        return out
    }

    /// On stop: the last guess becomes final, so the sitting's last words
    /// are judged rather than left unheard.
    mutating func flush() -> TranscriptFragment? {
        defer { lastVolatile = "" }
        return lastVolatile.isEmpty ? nil : .init(text: lastVolatile, isFinal: true)
    }

    private static func join(_ segments: ArraySlice<String>) -> String {
        segments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            // Whisper marks non-speech as e.g. "[موسيقى]"; it isn't recitation.
            .filter { !$0.isEmpty && !$0.hasPrefix("[") && !$0.hasPrefix("(") }
            .joined(separator: " ")
    }
}
