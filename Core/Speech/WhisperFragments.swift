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
    /// One transcribed segment; times are seconds into the sitting.
    struct Segment: Equatable {
        var text: String
        var start: Float
        var end: Float
    }

    /// Seconds into the sitting covered by the last final fragment.
    private(set) var finalSpan: ClosedRange<Float>?

    private var confirmedCount = 0
    private var confirmedEnd: Float = 0
    private var lastVolatile = ""
    /// Seconds covered by the current guess (its audio, if it is flushed).
    private var guessSpan: ClosedRange<Float>?

    /// Fragments for a new streaming state, given every confirmed segment so
    /// far and the unconfirmed ones.
    mutating func update(confirmed: [Segment], unconfirmed: [Segment]) -> [TranscriptFragment] {
        var out: [TranscriptFragment] = []
        if confirmed.count > confirmedCount {
            let new = confirmed[confirmedCount...]
            confirmedCount = confirmed.count
            confirmedEnd = max(confirmedEnd, new.map(\.end).max() ?? 0)
            let text = Self.join(new)
            if !text.isEmpty {
                out.append(.init(text: text, isFinal: true))
                finalSpan = (new.map(\.start).min() ?? 0)...confirmedEnd
            }
            lastVolatile = ""   // a final supersedes the guess: resend it
        }
        // WhisperKit publishes the confirmed list a moment before the new
        // guess, so for one update the guess still holds the words just
        // confirmed. Only segments after the confirmed audio are a guess.
        let guess = Self.join(unconfirmed.filter { $0.start >= confirmedEnd - 0.1 }[...])
        let guessed = unconfirmed.filter { $0.start >= confirmedEnd - 0.1 }
        guessSpan = guessed.isEmpty ? nil : (guessed.map(\.start).min() ?? 0)...(guessed.map(\.end).max() ?? 0)
        if guess != lastVolatile {
            lastVolatile = guess
            if !guess.isEmpty { out.append(.init(text: guess, isFinal: false)) }
        }
        return out
    }

    /// On stop: the last guess becomes final, so the sitting's last words
    /// are judged rather than left unheard. `finalSpan` becomes its audio.
    mutating func flush() -> TranscriptFragment? {
        defer { lastVolatile = ""; guessSpan = nil }
        guard !lastVolatile.isEmpty else { return nil }
        finalSpan = guessSpan
        return .init(text: lastVolatile, isFinal: true)
    }

    private static func join(_ segments: ArraySlice<Segment>) -> String {
        segments.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isNoise($0) }
            .joined(separator: " ")
    }

    /// Text Whisper produces for silence or noise rather than speech: its
    /// non-speech markers ("[موسيقى]") and lines from the subtitled videos it
    /// was trained on, which it repeats on near-silence (both seen live).
    static func isNoise(_ text: String) -> Bool {
        if text.hasPrefix("[") || text.hasPrefix("(") { return true }
        let norm = ArabicNormalize.normalize(text)
        return hallucinations.contains { norm.contains($0) }
    }

    private static let hallucinations = [
        "ترجمة نانسي قنقر", "نانسي قنقر", "موسيقي", "شكرا لك", "شكرا للمشاهدة",
        "اشتركوا في القناة", "اشترك في القناة", "لا تنسوا الاشتراك",
    ].map(ArabicNormalize.normalize)
}
