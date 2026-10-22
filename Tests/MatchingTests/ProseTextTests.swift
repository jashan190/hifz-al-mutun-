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
}
