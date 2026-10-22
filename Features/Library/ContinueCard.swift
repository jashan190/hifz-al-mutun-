// Features/Library/ContinueCard.swift
import SwiftUI

/// Pinned at the top of the Library: the matn the user is in the middle of,
/// with its position and a one-tap resume. Shown only when a last-read position
/// exists. Tapping opens the matn at its exact last page (handled by the caller).
struct ContinueCard: View {
    let matn: Matn
    let lastPage: Int

    private var color: Color { matn.subject.accent }

    private var currentBayt: Int {
        min(matn.baytCount, (lastPage - 1) * matn.baytsPerPage + 1)
    }
    private var progress: Double {
        matn.baytCount > 0 ? Double(currentBayt) / Double(matn.baytCount) : 0
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("تابِع الحفظ")
                .font(DisplayFont.body(size: 12))
                .foregroundStyle(.white.opacity(0.85))
            Text(matn.title)
                .font(DisplayFont.title(size: 24))
                .foregroundStyle(.white)
            // Prose has no bayts and no static total page count, so show just the
            // page and hide the bayt-based progress; poems keep both as before.
            Text(matn.kind == .prose
                 ? "صفحة \(Numerals.eastern(lastPage))"
                 : "صفحة \(Numerals.eastern(lastPage)) · البيت \(Numerals.eastern(currentBayt)) من \(Numerals.eastern(matn.baytCount))")
                .font(DisplayFont.body(size: 12))
                .foregroundStyle(.white.opacity(0.9))
            if matn.kind == .poem {
                ProgressView(value: progress)
                    .tint(.white)
                    .background(Capsule().fill(.white.opacity(0.25)))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color))
        .shadow(color: color.opacity(0.35), radius: 10, y: 5)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

#if DEBUG
#Preview {
    ContinueCard(matn: .preview, lastPage: 3)
        .padding()
        .background(Color(hex: 0xFBF8F1))
}
#endif
