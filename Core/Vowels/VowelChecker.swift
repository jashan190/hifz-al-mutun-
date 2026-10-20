import Foundation

/// Checks the harakat of words Whisper has already placed: runs the phoneme
/// model on their audio and reports each word with a short vowel said as
/// another, written as it was said (e.g. الْحَمْدَ for الْحَمْدُ), so the
/// reader can mark that letter.
///
/// Runs one clip at a time, off the main actor.
actor VowelChecker {
    private let model: any PhonemeHearing
    private let phonemes: [String?]
    private let written: [String]
    /// The runs of words of each check so far, in order (for tests and logs).
    private(set) var checked: [[[Int]]] = []

    init(model: any PhonemeHearing, phonemes: PhonemeIndex, written: [String]) {
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

    /// Slips among `runs` of words (flat indices, in order, each run said
    /// without a break and all of them in `audio`), by word: the word as it
    /// was said. A run with a word of unknown phonemes is left out; nothing
    /// when the clip doesn't suit the model.
    func check(runs: [[Int]], audio: [Float]) -> [Int: String] {
        let runs = runs.filter { run in !run.isEmpty && run.allSatisfy { phonemes.indices.contains($0) && phonemes[$0] != nil } }
        guard !runs.isEmpty else { return [:] }
        checked.append(runs)
        guard let heard = try? model.phonemes(audio) else { return [:] }
        let expected = runs.map { $0.map { phonemes[$0]! } }
        var out: [Int: String] = [:]
        for (r, slips) in VowelJudge.slips(runs: expected, heard: heard).enumerated() {
            for slip in slips {
                let i = runs[r][slip.word]
                let base = out[i] ?? written[i]
                if let said = VowelJudge.written(base, phonemes: expected[r][slip.word], vowel: slip.vowel, heard: slip.heard) {
                    out[i] = said
                }
            }
        }
        return out
    }
}
