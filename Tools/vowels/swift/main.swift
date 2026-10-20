// The app's vowel pipeline (Core/Vowels) run on the Mac's own Core ML, window
// by window over the parity fixtures, against what Python heard. The
// Simulator's Core ML can't run the model, so this is where Swift and Python
// are compared end to end.
//
//   swiftc -O -o /tmp/vowel-parity Core/Vowels/{PhonemeFeatures,PhonemeModel,VowelJudge}.swift Tools/vowels/swift/main.swift
//   /tmp/vowel-parity Muaalem_int8.mlpackage Tests/SpeechTests/Fixtures
//
// Given a folder of checks recorded live in the Simulator (by
// `vowelCheckIsQuietOnTheCorrectClip`), it instead judges each one as the app
// would and lists the slips:
//
//   /tmp/vowel-parity Muaalem_int8.mlpackage <folder>/checks.json
import Foundation
import AVFoundation

struct Window: Decodable { let from: Int; let to: Int; let phonemes: String }
struct Windows: Decodable { let windows: [Window] }

let args = CommandLine.arguments
let model = try PhonemeModel(contentsOf: URL(fileURLWithPath: args[1]))

if args[2].hasSuffix(".json") {
    struct Run: Decodable { let words: [String]; let phonemes: [String] }
    struct Check: Decodable { let audio: String; let runs: [Run] }
    struct Checks: Decodable { let checks: [Check] }
    let url = URL(fileURLWithPath: args[2])
    let checks = try JSONDecoder().decode(Checks.self, from: Data(contentsOf: url)).checks
    var slips = 0, words = 0
    for check in checks {
        let data = try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(check.audio))
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let said = check.runs.map { $0.words.joined(separator: " ") }.joined(separator: " | ")
        words += check.runs.map(\.words.count).reduce(0, +)
        guard let heard = try model.phonemes(samples) else {
            print("\(said): clip of \(samples.count / 16000) s not checked"); continue
        }
        let found = VowelJudge.slips(runs: check.runs.map(\.phonemes), heard: heard)
        let marks = zip(check.runs, found).flatMap { run, slips in
            slips.map { "\(run.words[$0.word]) vowel \($0.vowel): \(String($0.expected))→\(String($0.heard))" }
        }
        slips += marks.count
        print("\(String(format: "%5.1f", Double(samples.count) / 16000)) s  \(said)\(marks.isEmpty ? "" : "\n      SLIPS " + marks.joined(separator: ", "))")
    }
    print("\(checks.count) checks, \(words) words, \(slips) slips")
    exit(0)
}

let fixtures = URL(fileURLWithPath: args[2])
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
