import Foundation
import AVFoundation
import Speech

/// Errors a speech source can raise before it produces any audio.
enum SpeechSourceError: Error { case localeUnsupported, notAuthorized }

/// On-device model + permission helpers shared by the live and file sources.
@available(iOS 26, *)
enum SpeechModel {
    /// Request speech-recognition + microphone permission, or throw notAuthorized.
    static func requestAuthorization() async throws {
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { throw SpeechSourceError.notAuthorized }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard micOK else { throw SpeechSourceError.notAuthorized }
    }

    /// Ensure the on-device model for `locale` is supported and installed.
    static func ensureInstalled(_ transcriber: SpeechTranscriber, locale: Locale) async throws {
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) })
        else { throw SpeechSourceError.localeUnsupported }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}
