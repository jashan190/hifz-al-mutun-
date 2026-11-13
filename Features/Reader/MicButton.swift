import SwiftUI

// The voice button, shown in Memorize mode beside the toggle. Tapping it enters
// a "listening" state (cream mic → green, with a soft pulse). Its `isListening`
// binding drives `VoiceController` in `PageScreen`, which starts/stops a live
// `RecitationSession` (Apple's on-device `SpeechAnalyzer`) that reveals the
// matn word-by-word as the user recites.
struct MicButton: View {
    @Binding var isListening: Bool
    var tint: Color = Theme.accent   // the matn's subject colour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button {
            if reduceMotion { isListening.toggle() }
            else { withAnimation(.easeInOut(duration: 0.2)) { isListening.toggle() } }
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.onChrome)
                .frame(width: 38, height: 38)
                // Liquid Glass; it tints green while listening.
                .glassEffect(isListening ? .regular.tint(tint).interactive() : .regular.interactive(),
                             in: .circle)
                .overlay(
                    Circle()
                        .stroke(Theme.onChrome, lineWidth: 2)
                        .scaleEffect(pulse ? 1.45 : 1)
                        .opacity(pulse ? 0 : (isListening ? 0.7 : 0))
                )
        }
        .onChange(of: isListening) { _, listening in
            pulse = false
            if listening && !reduceMotion {
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
        .accessibilityLabel(isListening ? "Stop listening" : "Start voice recognition")
    }
}

#Preview {
    struct Demo: View {
        @State var on = false
        var body: some View { MicButton(isListening: $on).padding().background(Theme.chrome) }
    }
    return Demo()
}
