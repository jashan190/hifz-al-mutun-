// Features/Reader/ReaderSidecar.swift
import SwiftUI

/// The in-reader navigation panel: a page/bayt jump and the chapter list, as a
/// right-edge overlay. The current chapter is highlighted. Replaces the old
/// bottom index sheet. The caller owns presentation (overlay + scrim).
struct ReaderSidecar: View {
    let matn: Matn
    @Binding var currentPage: Int
    let onClose: () -> Void

    @State private var mode: JumpMode = .page
    @State private var goToPage = 1
    @State private var goToBayt = 1

    enum JumpMode: String, CaseIterable { case page = "صفحة", bayt = "بيت" }

    private func page(ofBayt bayt: Int) -> Int { (bayt - 1) / matn.baytsPerPage + 1 }
    private var currentBab: Bab? { matn.currentBab(onPage: currentPage) }

    var body: some View {
        VStack(spacing: 0) {
            header
            jump
            Divider().overlay(Theme.chromeHairline)
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

    private var jump: some View {
        VStack(spacing: 10) {
            Picker("", selection: $mode) {
                ForEach(JumpMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                if mode == .page {
                    NumberStepperField(value: $goToPage, range: 1...max(1, matn.pageCount))
                    GoButton { currentPage = goToPage; onClose() }
                } else {
                    NumberStepperField(value: $goToBayt, range: 1...max(1, matn.baytCount))
                    GoButton { currentPage = page(ofBayt: goToBayt); onClose() }
                }
            }
        }
        .padding(14)
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
