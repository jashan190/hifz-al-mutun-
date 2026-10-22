import SwiftUI

/// Renders one `HadithFragment`: the heading (first page), the right-aligned
/// body paragraph (Prophet's words in the subject colour), and the takhrīj
/// (last page). The folio is drawn by the containing `PageView`. Assumes the
/// RTL layout the app root already provides (so "leading" reads as the right).
struct ProsePageView: View {
    let fragment: HadithFragment
    let subjectColor: Color
    /// Fixed, comfortable reading size for prose (not auto-fitted like poems).
    var fontSize: CGFloat = 24

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            if fragment.isFirst {
                Text(fragment.title)
                    .font(DisplayFont.title(size: fontSize * 0.9))
                    .foregroundStyle(subjectColor)
                    .multilineTextAlignment(.center)
            }
            Text(ProseText.attributed(fragment.words, isnad: Theme.ink, matn: subjectColor))
                .font(PageFont.font(size: fontSize))
                .multilineTextAlignment(.leading)   // leading = right under RTL
                .lineSpacing(fontSize * 0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            if fragment.isLast && !fragment.takhrij.isEmpty {
                Text(fragment.takhrij)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
