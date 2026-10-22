import Testing
import UIKit
@testable import HifzAlMutun

@Suite struct ProseTextTests {
    private let words = [
        ProseWord(text: "عَنْ", normalized: "عن", role: .isnad),
        ProseWord(text: "إِنَّمَا", normalized: "انما", role: .matn),
    ]

    @Test func joinsWordsWithSpaces() {
        #expect(ProseText.plain(words) == "عَنْ إِنَّمَا")
    }

    @Test func bodyColoursByRoleAndJustifies() {
        let a = ProseText.body(words, font: .systemFont(ofSize: 20), lineSpacing: 8,
                               isnad: .black, matn: .red)
        #expect(a.string == "عَنْ إِنَّمَا")
        // The isnād word is isnād-coloured; the matn word is matn-coloured.
        #expect(a.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == .black)
        let matnIndex = (a.string as NSString).range(of: "إِنَّمَا").location
        #expect(a.attribute(.foregroundColor, at: matnIndex, effectiveRange: nil) as? UIColor == .red)
        // The paragraph is justified so lines fill the width evenly.
        let para = a.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(para?.alignment == .justified)
    }

    @Test func attributedAppliesPerWordColourAndUnderline() {
        let a = ProseText.attributed(words, font: .systemFont(ofSize: 20), lineSpacing: 8,
            color: { i, _ in i == 0 ? .green : .red },
            underline: { i in i == 1 ? .blue : nil })
        #expect(a.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == .green)
        let i2 = (a.string as NSString).range(of: "إِنَّمَا").location
        #expect(a.attribute(.foregroundColor, at: i2, effectiveRange: nil) as? UIColor == .red)
        #expect((a.attribute(.underlineStyle, at: i2, effectiveRange: nil) as? Int ?? 0) != 0)
        // The underline has its own colour (visible even when the glyph is not).
        #expect(a.attribute(.underlineColor, at: i2, effectiveRange: nil) as? UIColor == .blue)
        #expect((a.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) == 0)
    }

    @Test func attributedAppliesPerWordBackground() {
        let a = ProseText.attributed(words, font: .systemFont(ofSize: 20), lineSpacing: 8,
            color: { _, _ in .black }, underline: { _ in nil },
            background: { i in i == 1 ? .yellow : nil })
        let i2 = (a.string as NSString).range(of: "إِنَّمَا").location
        #expect(a.attribute(.backgroundColor, at: i2, effectiveRange: nil) as? UIColor == .yellow)
        #expect(a.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }
}
