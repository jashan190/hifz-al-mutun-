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

    /// A word to briefly flash after jumping to a mistake (then it clears).
    @State private var flashTarget: FlagKey?

    /// The cumulative review sheet.
    @State private var reviewPresented = false

    /// For prose: pages produced by the paginator for the current geometry, and
    /// the per-hadith index built from them. Empty for poems.
    @State private var prosePages: [MatnPage] = []
    @State private var proseBabs: [Bab] = []

    /// The pages the reader shows: poems come straight from the matn; prose is
    /// paginated at runtime.
    private var displayPages: [MatnPage] { matn.kind == .prose ? prosePages : matn.pages }
    private var displayPageCount: Int { displayPages.count }
    private var displayBabs: [Bab] { matn.kind == .prose ? proseBabs : matn.babs }

    init(matn: Matn, startOnCover: Bool = false) {
        self.matn = matn
        // Opening from a shelf cover lands on the title page (page 0). Resuming
        // (Continue) or a debug arg goes straight to the text page.
        let debugPage = UserDefaults.standard.integer(forKey: "openReaderPage")
        let page = debugPage > 0 ? debugPage : ReadingPosition.lastPage(of: matn.id) ?? 1
        // Prose has no static pageCount (0 until paginated at runtime), so don't
        // clamp to it here; prose is re-clamped in repaginateIfProse. Poems were
        // already within range.
        _currentPage = State(initialValue: startOnCover ? 0 : max(1, page))
    }

    var body: some View {
      // Outer GeometryReader gives the screen size so prose can be paginated at
      // runtime; poems ignore it (behaviour unchanged).
      GeometryReader { geo in
        TabView(selection: $currentPage) {
            // Page 0: the matn's title page — the same cover, filling the page.
            MatnCover(matn: matn, style: .page)
                .tag(0)
                .contentShape(Rectangle())
                .onTapGesture { toggleBars() }
            ForEach(displayPages, id: \.page) { pageModel in
                PageView(matn: matn, pageModel: pageModel, mode: mode,
                         reveal: mode == .memorize ? voice.reveal : nil,
                         flashTarget: flashTarget)
                    .tag(pageModel.page)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleBars() }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .task(id: geo.size) {
            guard matn.kind == .prose, geo.size.width > 0, geo.size.height > 0 else { return }
            let hadiths = matn.hadiths
            let size = geo.size
            let result = await Task.detached(priority: .userInitiated) {
                let fontSize = proseBodyFontSize
                let lineSpacing = ProsePageView.lineSpacing(for: fontSize)
                let contentWidth = size.width - Theme.margin * 2
                // Reserve the folio, margins, and slack for the title/takhrīj
                // blocks + inter-block spacing so a page never overflows — it
                // page-turns when full instead of scrolling.
                let bodyHeight = size.height - PageView.folioHeight - Theme.margin * 2 - 48
                let font = PageFont.uiFont(size: fontSize)
                return ProsePaginator.paginate(
                    hadiths,
                    bodyHeight: bodyHeight,
                    headingHeight: fontSize * 1.8,
                    takhrijHeight: 0,
                    measureBody: { ProsePaginator.bodyHeight($0, width: contentWidth,
                                                              font: font, lineSpacing: lineSpacing) })
            }.value
            // A newer geometry may have superseded this run while it was off the
            // main actor; don't clobber the current result with a stale one.
            guard !Task.isCancelled else { return }
            prosePages = result.pages
            proseBabs = hadiths.map {
                Bab(id: "h\($0.number)", title: $0.title, startPage: result.firstPageOf[$0.number] ?? 1)
            }
            if currentPage > result.pages.count { currentPage = max(1, result.pages.count) }
        }
        .onAppear { ReadingPosition.recordOpened(matn.id) }
        .environment(\.readerActions, actions)
        .background(Theme.cover.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { if barsVisible { topBar } }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if barsVisible { footer }
        }
        .sheet(isPresented: $reviewPresented) {
            ReviewSheet(
                matn: matn,
                annotations: voice.summary.map { ReviewItems.annotations($0) } ?? [:],
                onSelect: { key in reviewPresented = false; goToFlag(key) },
                onRemove: { key in flagStore.setFlag(false, matnID: matn.id, key) },
                reviewAgain: { reviewPresented = false; startVoice() },
                done: { reviewPresented = false })
            .environmentObject(flagStore)
        }
        .onChange(of: voice.summary != nil) { _, hasSummary in
            if hasSummary { reviewPresented = true }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .overlay {
            if showIndex {
                GeometryReader { geo in
                    ZStack(alignment: .trailing) {
                        // Scrim: dims the page, tap to dismiss.
                        Color.black.opacity(0.38)
                            .ignoresSafeArea()
                            .onTapGesture { showIndex = false }

                        ReaderSidecar(matn: matn, babs: displayBabs, pageCount: displayPageCount,
                                      currentPage: $currentPage,
                                      topInset: geo.safeAreaInsets.top) {
                            showIndex = false
                        }
                        .frame(width: geo.size.width * 0.8)
                        .frame(maxHeight: .infinity)
                        .background(Theme.page)
                        .transition(.opacity)
                    }
                    .ignoresSafeArea()
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showIndex)
        .onChange(of: currentPage) { _, page in
            // Page 0 is the cover — don't record it as a reading position.
            if page >= 1 { ReadingPosition.save(page: page, of: matn.id) }
            // Swiped (or jumped) by hand while reciting: carry on from this page.
            // (Only while a sitting runs: after a stop, swiping back to look at
            // the results must not reset them.)
            if voice.isActive, mode == .memorize, page >= 1, page != autoTurnTarget {
                voice.jump(toPage: page)
            }
            autoTurnTarget = nil
        }
        // Turn the page as soon as its last word is recited.
        .onChange(of: voice.cursor) { _, c in
            guard mode == .memorize, voice.isActive else { return }
            let resolved: Int?
            if matn.kind == .prose {
                // Prose pages are runtime; map the cursor's (hadith, word-in-body)
                // onto the page that holds that fragment.
                resolved = voice.proseRef(forCursor: c).flatMap {
                    prosePage(hadith: $0.hadith, wordInBody: $0.wordInBody)
                }
            } else {
                resolved = voice.page(forCursor: c)
            }
            guard let target = resolved, target != currentPage else { return }
            autoTurnTarget = target
            if reduceMotion { currentPage = target } else { withAnimation { currentPage = target } }
        }
        // A light buzz and a short tone when a new mistake is judged, so the
        // reciter notices without looking (as Tarteel does).
        .sensoryFeedback(.warning, trigger: voice.mistakeCount) { old, new in new > old }
        .onChange(of: voice.mistakeCount) { old, new in
            if new > old, voice.isLive { MistakeSound.play() }
        }
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
        // Debug-only: `-debugRecite` / `-debugVoiceFail` (see VoiceController),
        // or `-debugListen YES` (the real microphone), open straight into
        // Memorize and start a sitting.
        .onAppear {
            let d = UserDefaults.standard
            if d.string(forKey: "debugRecite") != nil || d.string(forKey: "debugVoiceFail") != nil
                || d.bool(forKey: "debugListen") {
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
    }

    private var actions: ReaderActions {
        ReaderActions(
            startFromBayt: { bayt in
                if voice.isLive { voice.jump(toBayt: bayt) } else { startVoice(bayt: bayt) }
            },
            revealNext: { _ in voice.revealNext() },
            dismissMistake: { bayt, half, word in
                voice.dismissMistake(bayt: bayt, half: half, wordIndex: word)
            },
            dismissAdded: { bayt, half, word in
                voice.dismissAdded(bayt: bayt, half: half, wordIndex: word)
            }
        )
    }

    /// The hadith number shown on the current page (prose), else nil.
    private var currentHadith: Int? {
        displayPages.first { $0.page == currentPage }?
            .items.compactMap { if case .hadith(let f) = $0 { return f.hadithNumber } else { return nil } }.first
    }

    /// The runtime prose page that holds this hadith's `wordInBody`, or nil.
    private func prosePage(hadith: Int, wordInBody: Int) -> Int? {
        for page in prosePages {
            for item in page.items {
                guard case .hadith(let f) = item, f.hadithNumber == hadith else { continue }
                if f.bodyStart <= wordInBody && wordInBody < f.bodyStart + f.words.count {
                    return page.page
                }
            }
        }
        return nil
    }

    /// Jump to a flagged/mistaken word and flash it.
    private func goToFlag(_ key: FlagKey) {
        let target: Int
        if matn.kind == .prose {
            target = prosePage(hadith: key.bayt, wordInBody: key.wordIndex) ?? max(1, currentPage)
        } else {
            target = min(max(1, matn.page(ofBayt: key.bayt)), max(1, displayPageCount))
        }
        if reduceMotion { currentPage = target } else { withAnimation { currentPage = target } }
        flashTarget = key
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if flashTarget == key { flashTarget = nil }
        }
    }

    private func startVoice(bayt: Int? = nil) {
        let seed = matn.kind == .prose ? currentHadith : bayt
        voice.start(matn: matn, fromPage: currentPage, bayt: seed, flags: flagStore)
    }

    private func setMode(_ m: PageMode) {
        if reduceMotion { mode = m } else { withAnimation(.easeInOut(duration: 0.22)) { mode = m } }
    }

    private func toggleBars() {
        if reduceMotion { barsVisible.toggle() }
        else { withAnimation(.easeInOut(duration: 0.2)) { barsVisible.toggle() } }
    }

    /// The header/footer/sidecar bar colour for this matn's subject.
    private var chrome: Color { Theme.subjectChrome(matn.subject) }
    /// The vivid subject accent, for controls on cream surfaces.
    private var subjectAccent: Color { matn.subject.accent }

    private var babsCaption: String {
        displayBabs.last { $0.startPage <= currentPage }?.title ?? ""
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ChromeIconButton(system: "chevron.backward", label: "Back to Library") { dismiss() }
            VStack(spacing: 2) {
                Text(matn.title)
                    .font(.headline)
                    .foregroundStyle(Theme.onChrome)
                if !babsCaption.isEmpty {
                    Text(babsCaption)
                        .font(.footnote)
                        .foregroundStyle(Theme.onChromeDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity)
            ChromeIconButton(system: "list.bullet", label: "Index") {
                showIndex = true
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 5)
        .background { chrome.ignoresSafeArea(edges: .top) }
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
                // Memorize + voice target both poems (per bayt) and prose (per
                // hadith): the toggle and mic are reachable for both.
                ModeToggle(mode: $mode, tint: subjectAccent)
                    .fixedSize()
                if mode == .memorize {
                    MicButton(isListening: Binding(
                        get: { voice.isLive },
                        set: { on in on ? startVoice() : voice.stop() }
                    ), tint: subjectAccent)
                    .transition(.scale.combined(with: .opacity))
                }
                Button { reviewPresented = true } label: {
                    let n = flagStore.count(for: matn.id)
                    HStack(spacing: 5) {
                        Image(systemName: "flag.fill").font(.system(size: 12, weight: .semibold))
                        Text(n > 0 ? "مراجعة · \(Numerals.eastern(n))" : "مراجعة")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(n > 0 ? Theme.onChrome : Theme.onChromeDim)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.onChrome.opacity(0.12)))
                }
                .buttonStyle(PressableStyle())
                .fixedSize()
                Spacer(minLength: 0)
                Text(currentPage >= 1
                     ? "\(Numerals.eastern(currentPage)) / \(Numerals.eastern(displayPageCount))"
                     : "الغلاف")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.onChromeDim)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 7)
        .background { chrome.ignoresSafeArea(edges: .bottom) }
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
            label("Downloading Arabic voice \(Int((p * 100).rounded()))% (once)")
        case .loadingModel:
            label("Preparing Arabic voice… the first time takes a minute.")
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
            if failure == .micDenied {
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
        case .downloadFailed: return "Couldn't download the Arabic voice. Connect to the internet and try again, or tap the blank to reveal."
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

#Preview("Reader") {
    NavigationStack { PageScreen(matn: .preview) }
}
