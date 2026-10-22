// Features/Reader/ReaderSidecar.swift
import SwiftUI

/// The in-reader navigation panel: a page/bayt jump and the baab (chapter) list,
/// as a right-edge overlay. Its header matches the reader's top bar (same size,
/// subject colour); accents follow the matn's subject too. The caller owns
/// presentation (overlay + scrim) and passes the top safe-area inset so the
/// header lines up with the reader's.
struct ReaderSidecar: View {
    let matn: Matn
    /// The resolved index (poems: matn.babs; prose: per-hadith, built at runtime).
    var babs: [Bab]
    @Binding var currentPage: Int
    var topInset: CGFloat = 0
    let onClose: () -> Void

    @State private var mode: JumpMode = .page
    @State private var goToPage = 1
    @State private var goToBayt = 1
    @FocusState private var fieldFocused: Bool

    enum JumpMode: String, CaseIterable { case page = "صفحة", bayt = "بيت" }

    private var bar: Color { Theme.subjectChrome(matn.subject) }
    private var accent: Color { matn.subject.accent }
    private var currentBab: Bab? { babs.last { $0.startPage <= currentPage } }
    /// Prose has no bayts (and no static pageCount), so only the page jump is
    /// offered; the max there is the index's last page.
    private var maxValue: Int {
        if matn.kind == .prose { return max(1, babs.map(\.startPage).max() ?? 1) }
        return mode == .page ? max(1, matn.pageCount) : max(1, matn.baytCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            jump
            if !babs.isEmpty {
                Divider().overlay(Theme.chromeHairline.opacity(0.4))
                baabsHeader
                chapterList
            } else {
                Spacer(minLength: 0)
            }
        }
        .background(Theme.page)
        .onAppear {
            // Prose offers only the page jump (no bayts).
            if matn.kind == .prose { mode = .page }
            goToPage = currentPage
            goToBayt = (currentPage - 1) * matn.baytsPerPage + 1
        }
    }

    // Mirrors PageScreen.topBar: a close button, a two-line title, and a balance
    // spacer, at the same padding and on the same subject-coloured bar.
    private var header: some View {
        HStack(spacing: 12) {
            ChromeIconButton(system: "xmark", label: "Close") { onClose() }
            VStack(spacing: 2) {
                Text(matn.title)
                    .font(.headline)
                    .foregroundStyle(Theme.onChrome)
                Text("الفهرس")
                    .font(.footnote)
                    .foregroundStyle(Theme.onChromeDim)
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(width: 30, height: 30)   // balances the close button
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, topInset + 5)
        .padding(.bottom, 5)
        .background { bar.ignoresSafeArea(edges: .top) }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
        }
    }

    // MARK: - Jump (type a number, confirm with اذهب; ± to nudge)

    private var jump: some View {
        VStack(spacing: 12) {
            // Poems can jump by page or by bayt; prose has no bayts, so the mode
            // picker is hidden and the jump stays on pages.
            if matn.kind == .poem {
                Picker("", selection: $mode) {
                    ForEach(JumpMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 14) {
                nudgeButton("minus") { nudge(-1) }
                Group {
                    if mode == .page {
                        TextField("", value: $goToPage, format: .number)
                    } else {
                        TextField("", value: $goToBayt, format: .number)
                    }
                }
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(accent)
                .focused($fieldFocused)
                .frame(maxWidth: .infinity)
                nudgeButton("plus") { nudge(1) }
            }

            Text("من \(Numerals.eastern(maxValue)) \(mode == .page ? "صفحة" : "بيت")")
                .font(.footnote)
                .foregroundStyle(Theme.numeral)

            Button(action: performJump) {
                Text("اذهب")
                    .font(DisplayFont.body(size: 17).weight(.bold))
                    .foregroundStyle(Theme.onChrome)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(14)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func nudgeButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(Circle().fill(accent.opacity(0.12)))
        }
        .buttonStyle(PressableStyle())
    }

    private func nudge(_ delta: Int) {
        if mode == .page { goToPage = min(maxValue, max(1, goToPage + delta)) }
        else { goToBayt = min(maxValue, max(1, goToBayt + delta)) }
    }

    private func performJump() {
        fieldFocused = false
        if mode == .page {
            currentPage = min(maxValue, max(1, goToPage))
        } else {
            currentPage = matn.page(ofBayt: min(maxValue, max(1, goToBayt)))
        }
        onClose()
    }

    // MARK: - Baabs (chapters)

    private var baabsHeader: some View {
        Text("الأبواب")
            .font(DisplayFont.body(size: 15).weight(.bold))
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .environment(\.layoutDirection, .rightToLeft)
    }

    private var chapterList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(babs) { bab in
                    let isCurrent = bab.id == currentBab?.id
                    Button {
                        currentPage = bab.startPage; onClose()
                    } label: {
                        HStack(spacing: 10) {
                            Text(bab.title)
                                .font(DisplayFont.body(size: 17))
                                .foregroundStyle(isCurrent ? accent : Theme.ink)
                            Spacer(minLength: 8)
                            Text("ص \(Numerals.eastern(bab.startPage))")
                                .font(.system(.footnote, design: .serif))
                                .foregroundStyle(Theme.numeral)
                        }
                        .padding(.vertical, 11).padding(.horizontal, 14)
                        .background(isCurrent ? accent.opacity(0.1) : .clear)
                        .overlay(alignment: .trailing) {
                            if isCurrent {
                                Rectangle().fill(accent).frame(width: 3)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    Divider().overlay(Theme.ink.opacity(0.06)).padding(.leading, 14)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
