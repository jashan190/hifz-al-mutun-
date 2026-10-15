import Testing
import Foundation
import Speech
@testable import HifzAlMutun

@Suite struct FileTranscriptionSpikeTests {
    @Test func listsSupportedLocales() async {
        let supported = await SpeechTranscriber.supportedLocales
        print("SUPPORTED LOCALES (\(supported.count)):")
        for loc in supported.sorted(by: { $0.identifier(.bcp47) < $1.identifier(.bcp47) }) {
            print("  \(loc.identifier(.bcp47))")
        }
        let installed = await SpeechTranscriber.installedLocales
        print("INSTALLED LOCALES (\(installed.count)):")
        for loc in installed { print("  \(loc.identifier(.bcp47))") }
        let hasArabic = supported.contains { $0.identifier(.bcp47).hasPrefix("ar") }
        print("ARABIC SUPPORTED: \(hasArabic)")
    }

    /// The on-device speech models ship only on physical devices; the
    /// Simulator reports zero supported locales.
    static var onSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // The device-only GATE for Apple's Arabic recognition (roadmap Phase A).
    // Skipped on the Simulator; on a phone, no Arabic model fails it.
    @Test(.disabled(if: onSimulator, "No speech models in the Simulator — run on a physical iOS 26+ device."))
    func transcribesArabicClip() async throws {
        let locale = try await SpeechModel.resolveLocale(Locale(identifier: "ar"))
        print("SPIKE Arabic locale: \(locale.identifier(.bcp47))")

        let url = try #require(
            Bundle(for: SpikeAnchor.self).url(forResource: "shatibiyya_clip", withExtension: "m4a"),
            "fixture clip missing from test bundle")
        let source = FileSpeechSource(url: url)
        var transcript = ""
        try await source.start()
        for await fragment in source.fragments where fragment.isFinal {
            transcript += fragment.text + " "
        }
        print("SPIKE transcript:\n\(transcript)")
        // Minimal signal: some Arabic came back. Tighten to an expected word
        // from the clip once we have run it once and seen the output.
        #expect(!transcript.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}

/// A class in the test module, so `Bundle(for:)` resolves the test bundle.
private final class SpikeAnchor {}
