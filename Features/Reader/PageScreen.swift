import SwiftUI

// The matn reader: one page per screen, swipe between pages (RTL, like an Arabic
// book), bound between deep Madinah-green "covers" (header + footer). Tapping the
// page hides the covers for distraction-free reading.
struct PageScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let matn: Matn
    @State private var currentPage = max(1, UserDefaults.standard.integer(forKey: "openReaderPage"))  // 1 unless a debug launch arg overrides
    @State private var mode: PageMode = .read
    @State private var barsVisible = true
    @State private var showIndex = false
    @State private var isListening = false
    @StateObject private var voice = VoiceController()

    var body: some View {
        TabView(selection: $currentPage) {
            ForEach(1...matn.pageCount, id: \.self) { page in
                PageView(matn: matn, page: page, mode: mode,
                         reveal: (mode == .memorize && page == currentPage) ? voice.reveal : nil)
                    .tag(page)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleBars() }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Theme.page.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { if barsVisible { topBar } }
        .safeAreaInset(edge: .bottom, spacing: 0) { if barsVisible { footer } }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showIndex) {
            IndexSheet(matn: matn, currentPage: $currentPage)
        }
        .onChange(of: isListening) { _, listening in
            if listening {
                voice.start(matn: matn, fromPage: currentPage)
            } else {
                voice.stop()
            }
        }
        // A light buzz when a new mistake is judged, so the reciter notices
        // without looking (as Tarteel does).
        .sensoryFeedback(.warning, trigger: voice.mistakeCount) { old, new in new > old }
        // Never leave the microphone running once the reader is gone.
        .onDisappear {
            isListening = false
            voice.clear()
        }
        #if DEBUG
        // Debug-only: `-debugRecite` (see VoiceController) opens straight into
        // Memorize and replays the scripted recitation.
        .onAppear {
            if UserDefaults.standard.string(forKey: "debugRecite") != nil {
                mode = .memorize
                isListening = true
            }
        }
        #endif
        .onChange(of: voice.cursor) { _, c in
            guard mode == .memorize, isListening, let target = voice.page(forCursor: c) else { return }
            if target != currentPage {
                withAnimation { currentPage = target }
            }
        }
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
        HStack(spacing: 12) {
            ModeToggle(mode: $mode)
            if mode == .memorize {
                MicButton(isListening: $isListening)
                    .transition(.scale.combined(with: .opacity))
                if voice.lockState == .lost {
                    Text("listening…")
                        .font(.caption2)
                        .foregroundStyle(Theme.onChromeDim)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
            Text("\(Numerals.eastern(currentPage)) / \(Numerals.eastern(matn.pageCount))")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.onChromeDim)
                .fixedSize()
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 7)
        .background { Theme.chrome.ignoresSafeArea(edges: .bottom) }
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onChange(of: mode) { _, m in
            if m != .memorize {
                isListening = false
                voice.clear()
            }
        }
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
