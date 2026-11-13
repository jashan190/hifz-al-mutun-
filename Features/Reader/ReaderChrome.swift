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
    /// Horizontal span reserved on the trailing (status-pill) side for the camera /
    /// Dynamic Island occlusion, so the controls shift clear as it expands.
    var islandReserve: CGFloat = 0
    /// Vertical centre of the status pill / island, so the top-bar controls line
    /// up with it exactly.
    var islandCenterY: CGFloat = 0
    let onBack: () -> Void
    let onIndex: () -> Void
    let onReview: () -> Void
    let onStartVoice: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Width of the vertical rail: a single, generous touch target.
    static let railWidth: CGFloat = 56
    /// Diameter of a chrome button — a compact Liquid Glass circle.
    private let buttonSize: CGFloat = 38

    private var micBinding: Binding<Bool> {
        Binding(get: { voice.isLive }, set: { on in on ? onStartVoice() : voice.stop() })
    }

    private var isCover: Bool { currentPage < 1 }

    var body: some View {
        if vertical { rail } else { bar }
    }

    // MARK: - Shared controls (cream disc + green glyph: big, high contrast)

    /// A Liquid Glass circle with a glyph — matches iOS 26 system controls.
    private func glassCircle(_ system: String, size: CGFloat = 16) -> some View {
        Image(systemName: system)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Theme.onChrome)
            .frame(width: buttonSize, height: buttonSize)
            .glassEffect(.regular.interactive(), in: .circle)
    }

    private func discButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { glassCircle(system) }
            .accessibilityLabel(label)
    }

    private var modeButton: some View {
        Button {
            let next: PageMode = mode == .read ? .memorize : .read
            if reduceMotion { mode = next } else { withAnimation(.easeInOut(duration: 0.22)) { mode = next } }
        } label: {
            glassCircle(mode == .read ? "book.closed.fill" : "eye.slash.fill")
        }
        .accessibilityLabel("Mode: \(mode == .read ? "Read" : "Memorize")")
        .accessibilityHint("Switches between Read and Memorize")
    }

    private var reviewButton: some View {
        Button(action: onReview) {
            glassCircle("flag.fill", size: 15)
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
        chrome
            .frame(maxWidth: .infinity)
            .frame(height: width)
            .overlay(alignment: .top) {
                HStack(spacing: 12) {
                    // Nav (back, index) sits on the right, just inside the reserved
                    // island span; actions and page number on the left.
                    Spacer(minLength: islandReserve)
                    navGroup
                    Spacer(minLength: 0)
                    actionGroup
                    pageText
                }
                .padding(.horizontal, Theme.margin)
                .frame(height: buttonSize)
                // Line the controls up with the status pill's vertical centre.
                .padding(.top, max(0, islandCenterY - buttonSize / 2))
            }
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
