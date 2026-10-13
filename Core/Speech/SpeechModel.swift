import Foundation
import AVFoundation
import Speech

/// Errors a speech source can raise before it produces any audio.
enum SpeechSourceError: Error, Equatable {
    case localeUnsupported
    case speechNotAuthorized
    case micNotAuthorized
}

/// On-device model + permission helpers shared by the live and file sources.
enum SpeechModel {
    /// Request speech-recognition + microphone permission, or throw which one
    /// was refused (so the UI can say which switch to turn on in Settings).
    static func requestAuthorization() async throws {
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { throw SpeechSourceError.speechNotAuthorized }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard micOK else { throw SpeechSourceError.micNotAuthorized }
    }

    /// The supported locale to transcribe `requested` with. iOS may list only
    /// regional variants (e.g. `ar-SA`), so a bare `ar` must be mapped to one
    /// rather than compared identifier-for-identifier.
    static func resolveLocale(_ requested: Locale) async throws -> Locale {
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            return match
        }
        let language = requested.language.languageCode
        let sameLanguage = await SpeechTranscriber.supportedLocales
            .filter { $0.language.languageCode == language }
            .sorted { $0.identifier(.bcp47) < $1.identifier(.bcp47) }
        // Prefer Saudi Arabic (closest to classical recitation), else the first.
        if let best = sameLanguage.first(where: { $0.region?.identifier == "SA" }) ?? sameLanguage.first {
            return best
        }
        throw SpeechSourceError.localeUnsupported
    }

    /// Ensure the on-device model for the transcriber is installed, reporting
    /// download progress (0…1) if it has to be fetched.
    static func ensureInstalled(_ transcriber: SpeechTranscriber,
                                progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
        else { return }   // already installed
        let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { p, _ in
            progress?(p.fractionCompleted)
        }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
    }
}
