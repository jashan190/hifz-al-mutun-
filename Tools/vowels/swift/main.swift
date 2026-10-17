// The app's vowel pipeline (Core/Vowels) run on the Mac's own Core ML, window
// by window over the parity fixtures, against what Python heard. The
// Simulator's Core ML can't run the model, so this is where Swift and Python
// are compared end to end.
//
//   swiftc -O -o /tmp/vowel-parity Core/Vowels/{PhonemeFeatures,PhonemeModel,VowelJudge}.swift Tools/vowels/swift/main.swift
//   /tmp/vowel-parity Muaalem_int8.mlpackage Tests/SpeechTests/Fixtures
import Foundation
import AVFoundation

struct Window: Decodable { let from: Int; let to: Int; let phonemes: String }
struct Windows: Decodable { let windows: [Window] }

let args = CommandLine.arguments
let fixtures = URL(fileURLWithPath: args[2])
let model = try PhonemeModel(contentsOf: URL(fileURLWithPath: args[1]))
let file = try AVAudioFile(forReading: fixtures.appendingPathComponent("shatibiyya_clip_16k.flac"))
let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
try file.read(into: buffer)
let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
let windows = try JSONDecoder().decode(Windows.self, from: Data(contentsOf: fixtures.appendingPathComponent("vowel_windows.json"))).windows

var same = 0, swaps = 0
var times: [Double] = []
for w in windows {
    let start = Date()
    let mine = try model.phonemes(Array(samples[w.from..<w.to])) ?? "(none)"
    times.append(Date().timeIntervalSince(start))
    if mine == w.phonemes { same += 1 } else {
        let differ = VowelJudge.slips(expected: [w.phonemes], heard: mine).count
        swaps += differ
        print("window at \(w.from / 16) ms differs (\(differ) vowels heard differently)\n  swift  \(mine)\n  python \(w.phonemes)")
    }
}
print("identical on \(same)/\(windows.count) windows, \(swaps) vowels heard differently; median \(Int(times.sorted()[times.count / 2] * 1000)) ms, first \(Int(times[0] * 1000)) ms")
