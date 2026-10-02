import SwiftUI

// Small, reusable pieces of our own design language — so screens don't lean on
// stock iOS controls.

/// A soft press: the control dips slightly and dims. Respects Reduce Motion.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Apply our serif display face (Apple's New York — a system font) for Latin
    /// headings, giving an editorial, scholarly feel without bundling a font.
    func serifDisplay(_ style: Font.TextStyle = .largeTitle, weight: Font.Weight = .bold) -> some View {
        font(.system(style, design: .serif).weight(weight))
    }
}

/// A gentle fade-and-rise on first appearance, staggered by `delay`. Calm, not
/// flashy. Skipped under Reduce Motion.
private struct AppearModifier: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                if reduceMotion { shown = true }
                else { withAnimation(.easeOut(duration: 0.45).delay(delay)) { shown = true } }
            }
    }
}

extension View {
    func appear(delay: Double = 0) -> some View { modifier(AppearModifier(delay: delay)) }
}

/// A number control you can type into *or* nudge with − / +. Clamped to `range`.
struct NumberStepperField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    private func clamp(_ v: Int) -> Int { min(max(v, range.lowerBound), range.upperBound) }

    var body: some View {
        HStack(spacing: 0) {
            step("minus") { value = clamp(value - 1) }
            Divider().frame(height: 22).overlay(Theme.ink.opacity(0.08))
            TextField("", value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(.body, design: .serif).weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 54)
                .onChange(of: value) { _, v in
                    let c = clamp(v)
                    if c != v { value = c }
                }
            Divider().frame(height: 22).overlay(Theme.ink.opacity(0.08))
            step("plus") { value = clamp(value + 1) }
        }
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.ink.opacity(0.1)))
    }

    private func step(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// A small circular "go" action in Madinah green.
struct GoButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.forward")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.onChrome)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Theme.accent))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Go")
    }
}

/// A circular icon button for the green chrome bars (back, index…).
struct ChromeIconButton: View {
    let system: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.onChrome)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.onChrome.opacity(0.12)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}
