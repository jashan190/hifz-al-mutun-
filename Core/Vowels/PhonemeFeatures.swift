import Foundation
import Accelerate

/// The phoneme model's input: a port of `SeamlessM4TFeatureExtractor`
/// (Hugging Face transformers), which the model was trained on.
///
/// - Kaldi-style 80-bin log-mel filterbank: 25 ms frames every 10 ms, the
///   samples scaled to 16-bit range, DC offset removed, pre-emphasis 0.97, a
///   Povey window, a 512-point FFT, triangles on the Kaldi mel scale.
/// - Each mel bin normalized over the clip (mean 0, unit variance).
/// - Pairs of frames stacked: 160 values every 20 ms.
///
/// `PhonemeFeatureTests` checks it against the Python extractor's output.
enum PhonemeFeatures {
    static let sampleRate = 16_000
    static let width = 160                    // values per output frame
    private static let frameLength = 400
    private static let hop = 160
    private static let fftLength = 512
    private static let bins = fftLength / 2 + 1
    private static let mels = 80

    /// The model's frames for 16 kHz mono `samples` (row-major, `width` per
    /// frame), and their count. Empty when the clip is under 25 ms.
    static func frames(_ samples: [Float]) -> (values: [Float], count: Int) {
        guard samples.count >= frameLength else { return ([], 0) }
        let n = 1 + (samples.count - frameLength) / hop
        var logMel = [Float](repeating: 0, count: n * mels)
        var buffer = [Double](repeating: 0, count: frameLength)
        var real = [Float](repeating: 0, count: fftLength / 2)
        var imag = [Float](repeating: 0, count: fftLength / 2)
        var outReal = [Float](repeating: 0, count: fftLength / 2)
        var outImag = [Float](repeating: 0, count: fftLength / 2)
        var power = [Double](repeating: 0, count: bins)

        for f in 0..<n {
            let start = f * hop
            for k in 0..<frameLength { buffer[k] = Double(samples[start + k]) * 32768 }
            let mean = buffer.reduce(0, +) / Double(frameLength)
            for k in 0..<frameLength { buffer[k] -= mean }
            for k in stride(from: frameLength - 1, to: 0, by: -1) { buffer[k] -= 0.97 * buffer[k - 1] }
            buffer[0] *= 1 - 0.97
            // Real FFT of the zero-padded frame: even samples in `real`, odd
            // in `imag` (vDSP's packed real format).
            for k in 0..<(fftLength / 2) {
                let a = 2 * k, b = 2 * k + 1
                real[k] = a < frameLength ? Float(buffer[a] * window[a]) : 0
                imag[k] = b < frameLength ? Float(buffer[b] * window[b]) : 0
            }
            vDSP_DFT_Execute(dft, real, imag, &outReal, &outImag)
            // vDSP's real DFT comes out doubled; bin 0 holds DC (real) and
            // the Nyquist bin (imaginary).
            power[0] = Double(outReal[0] / 2) * Double(outReal[0] / 2)
            power[bins - 1] = Double(outImag[0] / 2) * Double(outImag[0] / 2)
            for k in 1..<(bins - 1) {
                let re = Double(outReal[k] / 2), im = Double(outImag[k] / 2)
                power[k] = re * re + im * im
            }
            for m in 0..<mels {
                var e = 0.0
                for (k, w) in filters[m] { e += w * power[k] }
                logMel[f * mels + m] = Float(log(max(1.192092955078125e-07, e)))
            }
        }

        // Normalize each mel bin over the clip (unbiased variance).
        for m in 0..<mels {
            var sum = 0.0
            for f in 0..<n { sum += Double(logMel[f * mels + m]) }
            let mean = sum / Double(n)
            var squares = 0.0
            for f in 0..<n { let d = Double(logMel[f * mels + m]) - mean; squares += d * d }
            let sd = (squares / Double(max(1, n - 1)) + 1e-7).squareRoot()
            for f in 0..<n { logMel[f * mels + m] = Float((Double(logMel[f * mels + m]) - mean) / sd) }
        }

        // An odd frame count is padded with a frame of 1s (the extractor's
        // padding value), then pairs of frames are stacked.
        if n % 2 == 1 { logMel += [Float](repeating: 1, count: mels) }
        return (logMel, (n + 1) / 2)
    }

    // MARK: - Fixed tables

    private static let dft: vDSP_DFT_Setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(fftLength), .FORWARD)!

    /// Povey window: a Hann window (symmetric) to the power 0.85.
    private static let window: [Double] = (0..<frameLength).map { k in
        pow(0.5 - 0.5 * cos(2 * Double.pi * Double(k) / Double(frameLength - 1)), 0.85)
    }

    /// Each mel filter's non-zero weights, as (FFT bin, weight). Triangles
    /// are laid out in mel space from 20 Hz to 8 kHz (Kaldi, as torchaudio).
    private static let filters: [[(Int, Double)]] = {
        func mel(_ hz: Double) -> Double { 1127 * log(1 + hz / 700) }
        let low = mel(20), high = mel(Double(sampleRate / 2))
        let centers = (0..<(mels + 2)).map { low + (high - low) * Double($0) / Double(mels + 1) }
        let binMel = (0..<bins).map { mel(Double(sampleRate) / Double(fftLength) * Double($0)) }
        return (0..<mels).map { m in
            (0..<bins).compactMap { k in
                let down = (binMel[k] - centers[m]) / (centers[m + 1] - centers[m])
                let up = (centers[m + 2] - binMel[k]) / (centers[m + 2] - centers[m + 1])
                let w = max(0, min(down, up))
                return w > 0 ? (k, w) : nil
            }
        }
    }()
}
