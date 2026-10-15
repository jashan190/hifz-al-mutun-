import AVFoundation

/// The short tone played when a mistake is judged, so the reciter hears it
/// without looking (alongside the haptic). Settings can turn it off.
@MainActor
enum MistakeSound {
    static let enabledKey = "mistakeSound"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static let player: AVAudioPlayer? = {
        guard let url = Bundle.main.url(forResource: "mistake", withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = 0.7
        player.prepareToPlay()
        return player
    }()

    static func play() {
        guard isEnabled, let player else { return }
        // While listening, the audio session is play-and-record through the
        // speaker (WhisperKit's), so the tone plays over the microphone.
        player.currentTime = 0
        player.play()
    }
}
