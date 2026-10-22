import Testing
import SwiftUI
@testable import HifzAlMutun

@Suite struct ProseTextTests {
    @Test func joinsWordsWithSpaces() {
        let words = [
            ProseWord(text: "عَنْ", normalized: "عن", role: .isnad),
            ProseWord(text: "إِنَّمَا", normalized: "انما", role: .matn),
        ]
        let s = ProseText.plain(words)
        #expect(s == "عَنْ إِنَّمَا")
    }

    @Test func attributedColoursByRole() {
        let words = [
            ProseWord(text: "عَنْ", normalized: "عن", role: .isnad),
            ProseWord(text: "إِنَّمَا", normalized: "انما", role: .matn),
        ]
        let a = ProseText.attributed(words, isnad: .black, matn: .red)
        let runs = Array(a.runs)
        #expect(runs.count >= 2)
        #expect(String(a.characters).contains("عَنْ"))
        #expect(String(a.characters).contains("إِنَّمَا"))
        // The two roles must actually produce different colours.
        #expect(runs.first?.foregroundColor == .black)             // isnād
        #expect(runs.contains { $0.foregroundColor == .red })      // matn
    }
}
