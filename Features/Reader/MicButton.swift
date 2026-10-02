import SwiftUI

// The voice button, shown in Memorize mode beside the toggle. Tapping it enters
// a "listening" state (cream mic → green, with a soft pulse). The on-device
// recognition engine (WhisperKit) gets wired to this next; for now it toggles
// the listening state so the entry point is in place.
struct MicButton: View {
    @Binding var isListening: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button {
            if reduceMotion { isListening.toggle() }
            else { withAnimation(.easeInOut(duration: 0.2)) { isListening.toggle() } }
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isListening ? Theme.onChrome : Theme.accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(isListening ? Theme.accent : Theme.onChrome))
                .overlay(
                    Circle()
                        .stroke(Theme.onChrome, lineWidth: 2)
                        .scaleEffect(pulse ? 1.45 : 1)
                        .opacity(pulse ? 0 : (isListening ? 0.7 : 0))
                )
        }
        .buttonStyle(PressableStyle())
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
