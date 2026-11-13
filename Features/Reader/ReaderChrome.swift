import SwiftUI

/// The reader's controls as one component with two shapes: a horizontal **bottom
/// bar** (the Duo held upright) or a slim **vertical rail** on the trailing edge
/// (the Duo folded, or open on its side). Same controls, same order, either way.
/// On the Duo this replaces the old split header + footer — back and index live
/// here now, and the chapter name shows as a running head on the page.
struct ReaderChrome: View {
    @Binding var mode: PageMode
    @ObservedObject var voice: VoiceController
    let tint: Color            // subject accent (vivid, on cream)
    let chrome: Color          // subject chrome (bar background)
    let flagCount: Int
    let currentPage: Int
    let pageCount: Int
    let vertical: Bool
    /// Rail width — defaults to the slim toolbar width, but on the Duo's inner
    /// screen it's set to the camera/status reserved strip so the rail fills it.
    var width: CGFloat = ReaderChrome.railWidth
    /// Top padding so rail controls clear the status bar at the top of the strip.
    var topInset: CGFloat = 0
    let onBack: () -> Void
    let onIndex: () -> Void
    let onReview: () -> Void
    let onStartVoice: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Width of the vertical rail: a single 44-pt touch target, no wider — like
    /// Apple's slim vertical toolbar. The icons fill this width.
    static let railWidth: CGFloat = 44

    private var micBinding: Binding<Bool> {
        Binding(get: { voice.isLive }, set: { on in on ? onStartVoice() : voice.stop() })
    }

    private var isCover: Bool { currentPage < 1 }

    var body: some View {
        if vertical { rail } else { bar }
    }

    // MARK: - Bottom bar (adds back + index to the familiar footer controls)

    private var bar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if mode == .memorize {
                VoiceStatusLabel(voice: voice).transition(.opacity)
            }
            HStack(spacing: 12) {
                ChromeIconButton(system: "chevron.backward", label: "Back to Library", action: onBack)
                ChromeIconButton(system: "list.bullet", label: "Index", action: onIndex)
                ModeToggle(mode: $mode, tint: tint).fixedSize()
                if mode == .memorize {
                    MicButton(isListening: micBinding, tint: tint)
                        .transition(.scale.combined(with: .opacity))
                }
                reviewPill
                Spacer(minLength: 0)
                Text(isCover ? "الغلاف"
                     : "\(Numerals.eastern(currentPage)) / \(Numerals.eastern(pageCount))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.onChromeDim)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 7)
        .background { chrome.ignoresSafeArea(edges: .bottom) }
        .overlay(alignment: .top) { Rectangle().fill(Theme.chromeHairline).frame(height: 1) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var reviewPill: some View {
        Button(action: onReview) {
            HStack(spacing: 5) {
                Image(systemName: "flag.fill").font(.system(size: 12, weight: .semibold))
                Text(flagCount > 0 ? "مراجعة · \(Numerals.eastern(flagCount))" : "مراجعة")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(flagCount > 0 ? Theme.onChrome : Theme.onChromeDim)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Theme.onChrome.opacity(0.12)))
        }
        .buttonStyle(PressableStyle())
        .fixedSize()
    }

    // MARK: - Vertical rail

    private var rail: some View {
        VStack(spacing: 4) {
            railIcon("chevron.backward", label: "Back to Library", action: onBack)
            railIcon("list.bullet", label: "Index", action: onIndex)
            railModeButton
            if mode == .memorize {
                MicButton(isListening: micBinding, tint: tint)
                    .transition(.scale.combined(with: .opacity))
            }
            railReviewButton
            pageStack.padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.top, max(8, topInset))
        .padding(.bottom, 10)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background { chrome.ignoresSafeArea() }
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.chromeHairline).frame(width: 1) }
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    /// A plain, full-width toolbar icon — fills the slim rail, no floating circle.
    private func railIcon(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.onChrome)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private var railModeButton: some View {
        Button {
            let next: PageMode = mode == .read ? .memorize : .read
            if reduceMotion { mode = next } else { withAnimation(.easeInOut(duration: 0.22)) { mode = next } }
        } label: {
            Image(systemName: mode == .read ? "book.closed.fill" : "eye.slash.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.onChrome)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Mode: \(mode == .read ? "Read" : "Memorize")")
        .accessibilityHint("Switches between Read and Memorize")
    }

    private var railReviewButton: some View {
        Button(action: onReview) {
            Image(systemName: "flag.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(flagCount > 0 ? Theme.onChrome : Theme.onChromeDim)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if flagCount > 0 {
                        Text(Numerals.eastern(flagCount))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.onChrome)
                            .padding(3)
                            .background(Circle().fill(tint))
                            .offset(x: 2, y: 2)
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Review")
    }

    @ViewBuilder private var pageStack: some View {
        if isCover {
            Image(systemName: "book.closed")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.onChromeDim)
                .accessibilityLabel("Cover")
        } else {
            VStack(spacing: 2) {
                Text(Numerals.eastern(currentPage)).font(.system(size: 13, weight: .semibold))
                Rectangle().fill(Theme.onChromeDim).frame(width: 12, height: 1)
                Text(Numerals.eastern(pageCount)).font(.system(size: 11))
            }
            .foregroundStyle(Theme.onChromeDim)
            .accessibilityLabel("Page \(currentPage) of \(pageCount)")
        }
    }
}
