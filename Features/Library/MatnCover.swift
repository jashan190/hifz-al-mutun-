// Features/Library/MatnCover.swift
import SwiftUI

/// A poem's custom manuscript "title page": cream paper with a faint diamond
/// hatch, arabesque corner ornaments joined by thin edge rules, and the title
/// (Aref Ruqaa) + author/label/count (Amiri) — all in the subject's colour.
/// `shelf` is the small home thumbnail; `hero` a mid card; `page` fills the whole
/// screen as the reader's first (title) page.
struct MatnCover: View {
    let matn: Matn
    var style: Style = .shelf

    enum Style { case shelf, hero, page }

    private func sz(_ shelf: CGFloat, _ hero: CGFloat, _ page: CGFloat) -> CGFloat {
        switch style { case .shelf: shelf; case .hero: hero; case .page: page }
    }

    private var color: Color { matn.subject.accent }
    private var cream: Color { Theme.cover }
    private var titleSize: CGFloat { sz(20, 34, 46) }
    private var cornerSize: CGFloat { sz(34, 71, 96) }
    private var cartLabel: String {
        switch matn.kind {
        case .prose: return "حديث"
        case .poem:  return matn.meter.isEmpty ? "متن" : "منظومة"
        }
    }

    // Where the border lines sit, in from the edge. The hatch is clipped to this
    // so the texture stays inside the frame (never out in the margin).
    private var ruleInset: CGFloat { sz(3, 5, 6) }

    // Thin rules in the MIDDLE of each edge only — gaps are left at the corners
    // so no line runs under the corner ornaments. Set at the inset of #40's own
    // edge line so the segments read as a continuation of it.
    private var edgeRule: some View {
        let inset: CGFloat = ruleInset
        let gap: CGFloat = cornerSize * 0.86   // clear the corner motif
        return ZStack {
            Rectangle().fill(color.opacity(0.9)).frame(height: 1)
                .padding(.horizontal, gap).padding(.top, inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Rectangle().fill(color.opacity(0.9)).frame(height: 1)
                .padding(.horizontal, gap).padding(.bottom, inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            Rectangle().fill(color.opacity(0.9)).frame(width: 1)
                .padding(.vertical, gap).padding(.leading, inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            Rectangle().fill(color.opacity(0.9)).frame(width: 1)
                .padding(.vertical, gap).padding(.trailing, inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    var body: some View {
        if style == .page {
            cardStack
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(Rectangle().strokeBorder(color, lineWidth: 3))
        } else {
            let radius: CGFloat = style == .hero ? 7 : 5
            cardStack
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                // Subject-colour outline so the cover stands off the background.
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(color, lineWidth: style == .hero ? 2 : 1.5)
                )
                .shadow(color: .black.opacity(0.14), radius: style == .hero ? 10 : 6, y: 4)
                .aspectRatio(0.67, contentMode: .fit)   // portrait title-page proportion
        }
    }

    private var cardStack: some View {
        ZStack {
            cream
            // Texture only inside the border lines — never out in the margin.
            // Finer diamonds (smaller spacing) than the default.
            HatchBackground(spacing: 4).padding(ruleInset)
            edgeRule
            CornerOrnament(color: color, inset: sz(2, 3, 4), size: cornerSize)
            content
        }
    }

    private var content: some View {
        VStack(spacing: sz(5, 9, 12)) {
            Text(cartLabel)
                .font(DisplayFont.body(size: sz(7, 12, 15)))
                .foregroundStyle(color)
                .padding(.horizontal, sz(7, 12, 16))
                .padding(.vertical, sz(1, 2, 3))
                .overlay(Capsule().stroke(color.opacity(0.8), lineWidth: 1))
            Text(matn.title)
                .font(DisplayFont.title(size: titleSize))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if !matn.author.isEmpty {
                Text(matn.author)
                    .font(DisplayFont.body(size: sz(7.5, 13, 17)))
                    .foregroundStyle(Theme.ink.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, sz(15, 26, 36))
        .frame(maxHeight: .infinity, alignment: style == .page ? .center : .top)
        .padding(.top, style == .page ? 0 : sz(22, 46, 0))
        .overlay(alignment: .bottom) {
            // Pinned in the clear zone between the bottom corners.
            Text(matn.kind == .prose
                 ? "\(Numerals.eastern(matn.baytCount)) حديثًا"
                 : "\(Numerals.eastern(matn.baytCount)) بيت")
                .font(DisplayFont.body(size: sz(7.5, 12, 15)))
                .foregroundStyle(color.opacity(0.9))
                .padding(.bottom, style == .page ? 46 : sz(10, 18, 0))
        }
    }
}

#Preview("Shelf") {
    HStack {
        MatnCover(matn: .preview, style: .shelf).frame(width: 116)
        MatnCover(matn: .preview, style: .hero).frame(width: 220)
    }
    .padding()
    .background(Color(hex: 0xEADFC6))
}
