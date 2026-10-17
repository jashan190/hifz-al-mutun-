import Foundation

/// Checks the harakat of words Whisper has already placed: runs the phoneme
/// model on their audio and reports each word with a short vowel said as
/// another, written as it was said (e.g. الْحَمْدَ for الْحَمْدُ), so the
/// reader can mark that letter.
///
/// Runs one clip at a time, off the main actor.
actor VowelChecker {
    private let model: PhonemeModel
    private let phonemes: [String?]
    private let written: [String]
    /// Words checked so far (for tests and logs).
    private(set) var wordsChecked = 0

    init(model: PhonemeModel, phonemes: PhonemeIndex, written: [String]) {
        self.model = model
        self.phonemes = phonemes.words
        self.written = written
    }

    /// Where the model is, if one has been placed for this run. DEBUG builds
    /// read a path from `-vowelModel` (an `.mlpackage` or `.mlmodelc`);
    /// there is no download yet. Never in the Simulator: its Core ML crashes
    /// the app running this model (a segfault in its CPU shape kernel), while
    /// the Mac's runs it.
    static var modelURL: URL? {
        #if targetEnvironment(simulator)
        nil
        #elseif DEBUG
        UserDefaults.standard.string(forKey: "vowelModel").map { URL(fileURLWithPath: $0) }
        #else
        nil
        #endif
    }

    /// The model, loaded once per app run (compiling it takes a while).
    static func sharedModel() async -> PhonemeModel? { await ModelCache.shared.model() }

    private actor ModelCache {
        static let shared = ModelCache()
        private var loading: Task<PhonemeModel?, Never>?
        func model() async -> PhonemeModel? {
            if loading == nil {
                loading = Task.detached(priority: .utility) {
                    guard let url = VowelChecker.modelURL else { return nil }
                    return try? PhonemeModel(contentsOf: url)
                }
            }
            return await loading!.value
        }
    }

    /// Slips among `words` (flat indices, in order, all said in `audio`), by
    /// word: the word as it was said. Empty when any of them has unknown
    /// phonemes, or the clip doesn't suit the model.
    func check(words: [Int], audio: [Float]) -> [Int: String] {
        guard !words.isEmpty else { return [:] }
        var expected: [String] = []
        for i in words {
            guard phonemes.indices.contains(i), let p = phonemes[i] else { return [:] }
            expected.append(p)
        }
        guard let heard = try? model.phonemes(audio) else { return [:] }
        wordsChecked += words.count
        var out: [Int: String] = [:]
        for slip in VowelJudge.slips(expected: expected, heard: heard) {
            let i = words[slip.word]
            let base = out[i] ?? written[i]
            if let said = VowelJudge.written(base, phonemes: expected[slip.word], vowel: slip.vowel, heard: slip.heard) {
                out[i] = said
            }
        }
        return out
    }
}
