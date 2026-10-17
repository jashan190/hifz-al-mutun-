import Foundation
import CoreML

/// The phoneme recognizer that hears harakat: Quran Muaalem
/// (`obadx/muaalem-model-v3_2`, MIT), its phoneme head exported to Core ML by
/// `Tools/vowels/convert.py`. Audio in, the phonemes said out, written in the
/// Quran Phonetic Script: letters, the three short vowels, and madd and ghunna
/// as repeated letters.
/// Something that hears phonemes in 16 kHz mono audio: the model, or a
/// stand-in in tests.
protocol PhonemeHearing: Sendable {
    func phonemes(_ samples: [Float]) throws -> String?
}

final class PhonemeModel: PhonemeHearing, @unchecked Sendable {
    /// The longest clip the export accepts (1500 frames of 20 ms).
    static let maxSeconds: Double = 30
    /// The shortest: 50 frames.
    static let minSeconds: Double = 1

    private let model: MLModel
    /// The input lengths (in frames) the model takes, when it takes only
    /// some; a clip is padded up to the next one.
    private let lengths: [Int]?

    /// Loads a compiled model (`.mlmodelc`), or compiles an `.mlpackage` first.
    init(contentsOf url: URL) throws {
        let compiled = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try MLModel(contentsOf: compiled, configuration: config)
        let shapes = model.modelDescription.inputDescriptionsByName["input_features"]?
            .multiArrayConstraint?.shapeConstraint
        lengths = shapes?.type == .enumerated ? shapes?.enumeratedShapes.map { $0[1].intValue }.sorted() : nil
    }

    /// The phonemes said in 16 kHz mono `samples`; nil when the clip is too
    /// short or too long for the model.
    func phonemes(_ samples: [Float]) throws -> String? {
        let seconds = Double(samples.count) / Double(PhonemeFeatures.sampleRate)
        guard seconds >= Self.minSeconds, seconds <= Self.maxSeconds else { return nil }
        var (values, count) = PhonemeFeatures.frames(samples)
        var length = count
        if let lengths {
            // Pad with the clip's mean (0 after normalization); the padded
            // frames' output is dropped. Tested: no vowel heard differently.
            guard let fit = lengths.first(where: { $0 >= count }) else { return nil }
            values += [Float](repeating: 0, count: (fit - count) * PhonemeFeatures.width)
            length = fit
        }
        let input = MLShapedArray<Float>(scalars: values, shape: [1, length, PhonemeFeatures.width])
        let out = try model.prediction(from: MLDictionaryFeatureProvider(
            dictionary: ["input_features": MLMultiArray(input)]))
        guard let logProbs = out.featureValue(for: "log_probs")?.multiArrayValue else { return nil }
        return Self.greedy(MLShapedArray<Float>(converting: logProbs), frames: count)
    }

    /// Greedy CTC decoding of the first `frames` frames: the likeliest token
    /// per frame, repeats merged, blanks dropped.
    static func greedy(_ logProbs: MLShapedArray<Float>, frames: Int) -> String {
        let frames = min(frames, logProbs.shape[1]), classes = logProbs.shape[2]
        var text = ""
        var last = -1
        logProbs.withUnsafeShapedBufferPointer { p, _, _ in
            for t in 0..<frames {
                let row = p.baseAddress! + t * classes
                var best = 0
                for c in 1..<classes where row[c] > row[best] { best = c }
                if best != last, best != blank { text += vocabulary[best] }
                last = best
            }
        }
        return text
    }

    private static let blank = 0
    /// The phoneme head's tokens by id (id 0 is the CTC blank).
    static let vocabulary = [
        "", "\u{0621}", "\u{0628}", "\u{062A}", "\u{062B}", "\u{062C}", "\u{062D}", "\u{062E}", "\u{062F}",
        "\u{0630}", "\u{0631}", "\u{0632}", "\u{0633}", "\u{0634}", "\u{0635}", "\u{0636}", "\u{0637}",
        "\u{0638}", "\u{0639}", "\u{063A}", "\u{0641}", "\u{0642}", "\u{0643}", "\u{0644}", "\u{0645}",
        "\u{0646}", "\u{0647}", "\u{0648}", "\u{064A}", "\u{0627}", "\u{06E6}", "\u{06E5}", "\u{064E}",
        "\u{064F}", "\u{0650}", "\u{06EA}", "\u{0640}", "\u{0672}", "\u{0687}", "\u{06BA}", "\u{06FE}",
        "\u{06DC}", "\u{0619}",
    ]
}
