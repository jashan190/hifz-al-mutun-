// Features/Library/MatnCover.swift
import SwiftUI

/// A poem's custom manuscript "title page": cream paper with a faint diamond
/// hatch, a thin double-rule border, floral corner ornaments, and the title
/// (Aref Ruqaa) + author/label/count (Amiri) — all in the subject's colour.
/// Used at two sizes (hero and shelf) via `style`.
struct MatnCover: View {
    let matn: Matn
    var style: Style = .shelf

    enum Style { case hero, shelf }

    private var color: Color { matn.subject.accent }
    private var cream: Color { .dynamic(light: 0xF4EBD3, dark: 0x262320) }
    private var titleSize: CGFloat { style == .hero ? 34 : 20 }
    private var cornerSize: CGFloat { style == .hero ? 66 : 40 }
    private var cartLabel: String { matn.meter.isEmpty ? "متن" : "منظومة" }

    var body: some View {
        ZStack {
            cream
            HatchBackground()
            CornerOrnament(color: color, inset: style == .hero ? 6 : 4, size: cornerSize)
            doubleRule
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: style == .hero ? 10 : 7, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: style == .hero ? 10 : 6, y: 4)
        .aspectRatio(0.78, contentMode: .fit)   // portrait title-page proportion
    }

    private var doubleRule: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .strokeBorder(color.opacity(0.9), lineWidth: 1)
            .padding(style == .hero ? 10 : 7)
            .overlay(
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .strokeBorder(color.opacity(0.9), lineWidth: 1)
                    .padding(style == .hero ? 13 : 9)
            )
            .allowsHitTesting(false)
    }

    private var content: some View {
        VStack(spacing: style == .hero ? 10 : 5) {
            Text(cartLabel)
                .font(DisplayFont.body(size: style == .hero ? 12 : 7))
                .foregroundStyle(color)
                .padding(.horizontal, style == .hero ? 12 : 7)
                .padding(.vertical, style == .hero ? 2 : 1)
                .overlay(Capsule().stroke(color.opacity(0.8), lineWidth: 1))
            Text(matn.title)
                .font(DisplayFont.title(size: titleSize))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if style == .hero, !matn.author.isEmpty {
                Text(matn.author)
                    .font(DisplayFont.body(size: 12))
                    .foregroundStyle(Theme.ink.opacity(0.55))
            }
        }
        .padding(.horizontal, style == .hero ? 28 : 14)
        .overlay(alignment: .bottom) {
            Text("\(Numerals.eastern(matn.baytCount)) بيت")
                .font(DisplayFont.body(size: style == .hero ? 10 : 7))
                .foregroundStyle(color.opacity(0.85))
                .padding(.bottom, style == .hero ? 14 : 8)
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
