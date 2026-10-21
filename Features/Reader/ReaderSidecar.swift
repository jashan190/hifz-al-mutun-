// Features/Reader/ReaderSidecar.swift
import SwiftUI

/// The in-reader navigation panel: a page/bayt jump and the baab (chapter) list,
/// as a right-edge overlay. The current baab is highlighted. Replaces the old
/// bottom index sheet. The caller owns presentation (overlay + scrim).
struct ReaderSidecar: View {
    let matn: Matn
    @Binding var currentPage: Int
    let onClose: () -> Void

    @State private var mode: JumpMode = .page
    @State private var goToPage = 1
    @State private var goToBayt = 1
    @FocusState private var fieldFocused: Bool

    enum JumpMode: String, CaseIterable { case page = "صفحة", bayt = "بيت" }

    private var currentBab: Bab? { matn.currentBab(onPage: currentPage) }
    private var maxValue: Int { mode == .page ? max(1, matn.pageCount) : max(1, matn.baytCount) }

    var body: some View {
        VStack(spacing: 0) {
            header
            jump
            Divider().overlay(Theme.chromeHairline)
            baabsHeader
            chapterList
        }
        .background(Theme.page)
        .onAppear {
            goToPage = currentPage
            goToBayt = (currentPage - 1) * matn.baytsPerPage + 1
        }
    }

    private var header: some View {
        HStack {
            Text(matn.title)
                .font(DisplayFont.title(size: 22))
                .foregroundStyle(Theme.onChrome)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.onChrome)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.onChrome.opacity(0.15)))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.chrome)
    }

    // MARK: - Jump (type a number, confirm with اذهب; ± to nudge)

    private var jump: some View {
        VStack(spacing: 12) {
            Picker("", selection: $mode) {
                ForEach(JumpMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

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
                .foregroundStyle(Theme.accent)
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
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent))
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
                .foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Theme.accent.opacity(0.12)))
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
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .environment(\.layoutDirection, .rightToLeft)
    }

    private var chapterList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(matn.babs) { bab in
                    let isCurrent = bab.id == currentBab?.id
                    Button {
                        currentPage = bab.startPage; onClose()
                    } label: {
                        HStack(spacing: 10) {
                            Text(bab.title)
                                .font(DisplayFont.body(size: 17))
                                .foregroundStyle(isCurrent ? Theme.accent : Theme.ink)
                            Spacer(minLength: 8)
                            Text("ص \(Numerals.eastern(bab.startPage))")
                                .font(.system(.footnote, design: .serif))
                                .foregroundStyle(Theme.numeral)
                        }
                        .padding(.vertical, 11).padding(.horizontal, 14)
                        .background(isCurrent ? Theme.accent.opacity(0.1) : .clear)
                        .overlay(alignment: .trailing) {
                            if isCurrent {
                                Rectangle().fill(Theme.accent).frame(width: 3)
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
