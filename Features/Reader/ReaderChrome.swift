import SwiftUI

/// The reader's controls as one component with two shapes: a **vertical rail** in
/// the camera/status strip on the trailing edge (the Duo folded, or open on its
/// side) or a **horizontal top bar** in the top camera/status strip (the Duo open
/// upright). Same controls either way — navigation (back, index) at the leading
/// end/top, actions (mode, review) at the trailing end/bottom. On the Duo this
/// replaces the old split header + footer; the chapter shows as a running head.
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
    /// Padding so controls clear the status bar / camera at the top of the strip.
    var topInset: CGFloat = 0
    let onBack: () -> Void
    let onIndex: () -> Void
    let onReview: () -> Void
    let onStartVoice: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Width of the vertical rail: a single, generous touch target.
    static let railWidth: CGFloat = 56
    /// Diameter of a chrome button — big, with a cream disc for strong contrast.
    private let buttonSize: CGFloat = 46

    private var micBinding: Binding<Bool> {
        Binding(get: { voice.isLive }, set: { on in on ? onStartVoice() : voice.stop() })
    }

    private var isCover: Bool { currentPage < 1 }

    var body: some View {
        if vertical { rail } else { bar }
    }

    // MARK: - Shared controls (cream disc + green glyph: big, high contrast)

    private func discButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(chrome)
                .frame(width: buttonSize, height: buttonSize)
                .background(Circle().fill(Theme.onChrome))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private var modeButton: some View {
        Button {
            let next: PageMode = mode == .read ? .memorize : .read
            if reduceMotion { mode = next } else { withAnimation(.easeInOut(duration: 0.22)) { mode = next } }
        } label: {
            Image(systemName: mode == .read ? "book.closed.fill" : "eye.slash.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(chrome)
                .frame(width: buttonSize, height: buttonSize)
                .background(Circle().fill(Theme.onChrome))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Mode: \(mode == .read ? "Read" : "Memorize")")
        .accessibilityHint("Switches between Read and Memorize")
    }

    private var reviewButton: some View {
        Button(action: onReview) {
            Image(systemName: "flag.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(chrome)
                .frame(width: buttonSize, height: buttonSize)
                .background(Circle().fill(Theme.onChrome))
                .overlay(alignment: .topTrailing) {
                    if flagCount > 0 {
                        Text(Numerals.eastern(flagCount))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.onChrome)
                            .padding(4)
                            .background(Circle().fill(tint))
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Review")
    }

    // Navigation group (back, index) and action group (mode, mic, review) — the
    // two ends of the bar/rail.
    @ViewBuilder private var navGroup: some View {
        discButton("chevron.backward", label: "Back to Library", action: onBack)
        discButton("list.bullet", label: "Index", action: onIndex)
    }

    @ViewBuilder private var actionGroup: some View {
        modeButton
        if mode == .memorize {
            MicButton(isListening: micBinding, tint: tint)
                .transition(.scale.combined(with: .opacity))
        }
        reviewButton
    }

    // MARK: - Horizontal top bar (Duo open, upright)

    private var bar: some View {
        HStack(spacing: 12) {
            navGroup
            Spacer(minLength: 0)
            actionGroup
            pageText
        }
        .padding(.horizontal, Theme.margin)
        // A strip the same thickness as the landscape rail's width, with its green
        // running up to the top edge behind the status bar / Dynamic Island; the
        // buttons stay below the time/wifi so they never overlap it.
        .frame(height: width)
        .frame(maxWidth: .infinity)
        .background { chrome.ignoresSafeArea(edges: .top) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.chromeHairline).frame(height: 1) }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // Page indicator, always read left-to-right ("٣ / ٦"); a book glyph on the cover.
    @ViewBuilder private var pageText: some View {
        if isCover {
            Image(systemName: "book.closed")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.onChromeDim)
                .accessibilityLabel("Cover")
        } else {
            // The leading LRM (U+200E) forces a left-to-right reading: "٣ / ٦".
            Text("\u{200E}\(Numerals.eastern(currentPage)) / \(Numerals.eastern(pageCount))")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.onChromeDim)
                .environment(\.layoutDirection, .leftToRight)
                .fixedSize()
                .accessibilityLabel("Page \(currentPage) of \(pageCount)")
        }
    }

    // MARK: - Vertical rail (Duo folded or on its side)

    private var rail: some View {
        VStack(spacing: 12) {
            navGroup
            Spacer(minLength: 0)
            pageText            // page number centred in the middle of the rail
            Spacer(minLength: 0)
            actionGroup
        }
        // Clear the status bar / Dynamic Island pill at the top of the camera
        // strip, leaving a comfortable gap so the top controls are tappable.
        .padding(.top, max(104, topInset + 28))
        .padding(.bottom, 16)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background { chrome.ignoresSafeArea() }
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.chromeHairline).frame(width: 1) }
        .transition(.move(edge: .leading).combined(with: .opacity))
    }
}
