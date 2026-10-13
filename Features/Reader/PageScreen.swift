import SwiftUI

// The matn reader: one page per screen, swipe between pages (RTL, like an Arabic
// book), bound between deep Madinah-green "covers" (header + footer). Tapping the
// page hides the covers for distraction-free reading.
struct PageScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var flagStore: FlagStore

    let matn: Matn
    @State private var currentPage: Int
    @State private var mode: PageMode = .read
    @State private var barsVisible = true
    @State private var showIndex = false
    @StateObject private var voice = VoiceController()
    /// The page an automatic turn is heading to, so it isn't taken for the
    /// reciter swiping by hand (which restarts tracking from that page).
    @State private var autoTurnTarget: Int?

    init(matn: Matn) {
        self.matn = matn
        // A debug launch arg wins; otherwise reopen at the last page read.
        let debugPage = UserDefaults.standard.integer(forKey: "openReaderPage")
        let page = debugPage > 0 ? debugPage : ReadingPosition.lastPage(of: matn.id) ?? 1
        _currentPage = State(initialValue: min(max(1, page), matn.pageCount))
    }

    var body: some View {
        TabView(selection: $currentPage) {
            ForEach(1...matn.pageCount, id: \.self) { page in
                PageView(matn: matn, page: page, mode: mode,
                         reveal: mode == .memorize ? voice.reveal : nil)
                    .tag(page)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleBars() }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.readerActions, actions)
        .background(Theme.page.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { if barsVisible { topBar } }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let summary = voice.summary, mode == .memorize {
                    SummaryCard(summary: summary,
                                reviewAgain: { startVoice() },
                                backToRead: { setMode(.read) })
                        .padding(.horizontal, Theme.margin)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if barsVisible { footer }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showIndex) {
            IndexSheet(matn: matn, currentPage: $currentPage)
        }
        .onChange(of: currentPage) { _, page in
            ReadingPosition.save(page: page, of: matn.id)
            // Swiped (or jumped) by hand while reciting: carry on from this page.
            // (Only while a sitting runs: after a stop, swiping back to look at
            // the results must not reset them.)
            if voice.isActive, mode == .memorize, page != autoTurnTarget {
                voice.jump(toPage: page)
            }
            autoTurnTarget = nil
        }
        // Turn the page as soon as its last word is recited.
        .onChange(of: voice.cursor) { _, c in
            guard mode == .memorize, voice.isActive,
                  let target = voice.page(forCursor: c), target != currentPage else { return }
            autoTurnTarget = target
            if reduceMotion { currentPage = target } else { withAnimation { currentPage = target } }
        }
        // A light buzz when a new mistake is judged, so the reciter notices
        // without looking (as Tarteel does).
        .sensoryFeedback(.warning, trigger: voice.mistakeCount) { old, new in new > old }
        // A light tap when a flag is set by hand (not by voice, which has its own).
        .sensoryFeedback(.impact(weight: .light), trigger: flagStore.count(for: matn.id)) { old, new in
            new > old && (mode == .read || !voice.isLive)
        }
        // Voice couldn't start (no permission, no Arabic model): Review carries
        // on by tap from the same place (UX.md "Without voice").
        .onChange(of: voice.status) { _, status in
            if case .failed = status, mode == .memorize {
                voice.fallBackToManual(matn: matn, page: currentPage)
            }
        }
        // Never leave the microphone running once the reader is gone.
        .onDisappear { voice.clear() }
        #if DEBUG
        // Debug-only: `-debugRecite` / `-debugVoiceFail` (see VoiceController)
        // open straight into Memorize and start a sitting.
        .onAppear {
            let d = UserDefaults.standard
            if d.string(forKey: "debugRecite") != nil || d.string(forKey: "debugVoiceFail") != nil {
                mode = .memorize
                startVoice()
            }
            // `-debugStopAfter 5` stops the sitting after 5 s (shows the summary).
            let stopAfter = d.double(forKey: "debugStopAfter")
            if stopAfter > 0 {
                Task {
                    try? await Task.sleep(for: .seconds(stopAfter))
                    voice.stop()
                }
            }
        }
        #endif
    }

    private var actions: ReaderActions {
        ReaderActions(
            startFromBayt: { bayt in
                if voice.isLive { voice.jump(toBayt: bayt) } else { startVoice(bayt: bayt) }
            },
            revealNext: { _ in voice.revealNext() },
            dismissMistake: { bayt, half, word in
                voice.dismissMistake(bayt: bayt, half: half, wordIndex: word)
            }
        )
    }

    private func startVoice(bayt: Int? = nil) {
        voice.start(matn: matn, fromPage: currentPage, bayt: bayt, flags: flagStore)
    }

    private func setMode(_ m: PageMode) {
        if reduceMotion { mode = m } else { withAnimation(.easeInOut(duration: 0.22)) { mode = m } }
    }

    private func toggleBars() {
        if reduceMotion { barsVisible.toggle() }
        else { withAnimation(.easeInOut(duration: 0.2)) { barsVisible.toggle() } }
    }

    private var babsCaption: String {
        matn.currentBab(onPage: currentPage)?.title ?? ""
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ChromeIconButton(system: "chevron.backward", label: "Back to Library") { dismiss() }
            VStack(spacing: 2) {
                Text(matn.title)
                    .font(.headline)
                    .foregroundStyle(Theme.onChrome)
                Text(babsCaption)
                    .font(.footnote)
                    .foregroundStyle(Theme.onChromeDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            ChromeIconButton(system: "list.bullet", label: "Index") { showIndex = true }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 5)
        .background { Theme.chrome.ignoresSafeArea(edges: .top) }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            // What voice review is doing, on its own line so it never squeezes
            // the controls.
            if mode == .memorize {
                VoiceStatusLabel(voice: voice)
                    .transition(.opacity)
            }
            HStack(spacing: 12) {
                ModeToggle(mode: $mode)
                    .fixedSize()
                if mode == .memorize {
                    MicButton(isListening: Binding(
                        get: { voice.isLive },
                        set: { on in on ? startVoice() : voice.stop() }
                    ))
                    .transition(.scale.combined(with: .opacity))
                }
                Spacer(minLength: 0)
                Text("\(Numerals.eastern(currentPage)) / \(Numerals.eastern(matn.pageCount))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.onChromeDim)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 7)
        .background { Theme.chrome.ignoresSafeArea(edges: .bottom) }
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onChange(of: mode) { _, m in
            if m != .memorize { voice.clear() }
        }
    }
}

// Beside the mic: what voice review is doing, and what to do when it can't
// (UX.md: "the mic button says why and offers … Open Settings").
private struct VoiceStatusLabel: View {
    @ObservedObject var voice: VoiceController
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch voice.status {
        case .preparing:
            label("Getting ready…")
        case .downloading(let p):
            label("Downloading Arabic voice \(Int((p * 100).rounded()))%")
        case .listening:
            if voice.isManual {
                if let failure = voice.voiceFailure { failed(failure) } else { label("Tap the blank to reveal the next word.") }
            } else if voice.lockState == .lost {
                label("listening…")
            }
        case .failed(let failure):
            failed(failure)
        case .idle:
            EmptyView()
        }
    }

    private func failed(_ failure: VoiceFailure) -> some View {
        HStack(spacing: 8) {
            label(message(failure))
            if failure == .micDenied || failure == .speechDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.onChrome)
                .fixedSize()
            }
        }
    }

    private func message(_ failure: VoiceFailure) -> String {
        switch failure {
        case .micDenied: return "Microphone is off. Tap the blank to reveal."
        case .speechDenied: return "Speech recognition is off. Tap the blank to reveal."
        case .arabicUnsupported: return "No Arabic voice on this device. Tap the blank to reveal."
        case .other: return "Voice isn't available. Tap the blank to reveal."
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.onChrome.opacity(0.85))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// Shown when a Review sitting stops (UX.md): what was covered, then Review
// again or go back to reading.
private struct SummaryCard: View {
    let summary: ReviewSummary
    let reviewAgain: () -> Void
    let backToRead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review finished")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 18) {
                stat(summary.baytsRecited, summary.baytsRecited == 1 ? "bayt recited" : "bayts recited")
                stat(summary.mistakes, summary.mistakes == 1 ? "mistake" : "mistakes")
                if summary.revealed > 0 { stat(summary.revealed, "revealed") }
            }
            HStack(spacing: 10) {
                Button(action: reviewAgain) {
                    Text("Review again").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: backToRead) {
                    Text("Back to Read").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .tint(Theme.accent)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(n)").font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
            Text(label).font(.caption).foregroundStyle(Theme.ink.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }
}

// A custom index — our own layout, not a stock List: a Jump card (type or step
// to a page / bayt) above a hand-styled list of abwab with their pages.
private struct IndexSheet: View {
    let matn: Matn
    @Binding var currentPage: Int
    @Environment(\.dismiss) private var dismiss
    @State private var goToPage = 1
    @State private var goToBayt = 1

    private func page(ofBayt bayt: Int) -> Int { (bayt - 1) / matn.baytsPerPage + 1 }
    private func startPage(of bab: Bab) -> Int { bab.startPage }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 18) {
                    jumpCard
                    babList
                }
                .padding(Theme.margin)
            }
        }
        .background(Theme.page.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { goToPage = currentPage; goToBayt = (currentPage - 1) * matn.baytsPerPage + 1 }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("الفهرس").font(.subheadline).foregroundStyle(Theme.accent)
                Text("Index").serifDisplay(.title2).foregroundStyle(Theme.ink)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.ink.opacity(0.06)))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, Theme.margin)
        .padding(.bottom, 10)
    }

    private var jumpCard: some View {
        VStack(spacing: 12) {
            jumpRow(label: "Page", total: matn.pageCount, value: $goToPage) {
                currentPage = goToPage; dismiss()
            }
            Rectangle().fill(Theme.ink.opacity(0.07)).frame(height: 1)
            jumpRow(label: "Bayt", total: matn.baytCount, value: $goToBayt) {
                currentPage = page(ofBayt: goToBayt); dismiss()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink.opacity(0.06)))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func jumpRow(label: String, total: Int, value: Binding<Int>, go: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(.headline, design: .serif)).foregroundStyle(Theme.ink)
                Text("of \(total)").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            NumberStepperField(value: value, range: 1...max(1, total))
            GoButton(action: go)
        }
    }

    private var babList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("الأبواب")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(matn.babs.enumerated()), id: \.element.id) { i, bab in
                    Button {
                        currentPage = startPage(of: bab); dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(bab.title)
                                .font(.body)
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Text(Numerals.eastern(startPage(of: bab)))
                                .font(.system(.subheadline, design: .serif).weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(minWidth: 30, minHeight: 30)
                                .background(Capsule().fill(Theme.accent.opacity(0.1)))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())

                    if i < matn.babs.count - 1 {
                        Rectangle().fill(Theme.ink.opacity(0.06)).frame(height: 1)
                            .padding(.leading, 14)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.ink.opacity(0.06)))
        }
    }
}

#Preview("Reader") {
    NavigationStack { PageScreen(matn: .preview) }
}
