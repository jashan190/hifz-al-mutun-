import Foundation

/// The phonemes expected for each word of a matn, parallel to a
/// `RecitationIndex`'s flat words. Built ahead of time from the vowelled text
/// by `Tools/vowels/build_phonemes.py` into `Resources/Phonemes/<matn id>.phonemes.json`.
struct PhonemeIndex {
    /// By flat word index: the word's phonemes, "" for a word with nothing to
    /// say, or nil where they aren't known (that half-line is left to Whisper).
    let words: [String?]

    private struct File: Decodable {
        let version: Int
        let halves: [String: [String?]]
    }

    init?(matnID: String, index: RecitationIndex, bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "\(matnID).phonemes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data), file.version == 1
        else { return nil }
        self.init(halves: file.halves, index: index)
    }

    init(halves: [String: [String?]], index: RecitationIndex) {
        words = index.refs.map { ref in
            let half = halves["\(ref.bayt).\(ref.half == .sadr ? "sadr" : "ajuz")"]
            guard let half, half.indices.contains(ref.wordIndex) else { return nil }
            return half[ref.wordIndex]
        }
    }
}
