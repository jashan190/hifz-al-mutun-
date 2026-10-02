import SwiftUI

// A small bespoke pill that flips the page between Read and Memorize. It shows
// the current mode with a swap glyph, so one tap switches. Not a stock iOS
// segmented control.
struct ModeToggle: View {
    @Binding var mode: PageMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            let next: PageMode = (mode == .read) ? .memorize : .read
            if reduceMotion { mode = next }
            else { withAnimation(.easeInOut(duration: 0.22)) { mode = next } }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode == .read ? "book.closed.fill" : "eye.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(mode == .read ? "Read" : "Memorize")
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.55)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.onChrome))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Mode: \(mode == .read ? "Read" : "Memorize")")
        .accessibilityHint("Switches between Read and Memorize")
    }
}

#Preview {
    struct Demo: View {
        @State var mode: PageMode = .read
        var body: some View {
            ModeToggle(mode: $mode).padding().background(Theme.chrome)
        }
    }
    return Demo()
}
