import Testing
import Foundation
@testable import HifzAlMutun

@Suite struct ProseModelTests {
    @Test func proseWordDecodesRole() throws {
        let json = #"{"text":"إِنَّمَا","norm":"انما","role":"matn"}"#.data(using: .utf8)!
        let w = try JSONDecoder().decode(ProseWord.self, from: json)
        #expect(w.text == "إِنَّمَا")
        #expect(w.normalized == "انما")
        #expect(w.role == .matn)
    }

    @Test func hadithDecodesFully() throws {
        let json = """
        {"number":1,"title":"الحديث الأول",
         "body":[{"text":"عَنْ","norm":"عن","role":"isnad"},
                 {"text":"إِنَّمَا","norm":"انما","role":"matn"}],
         "takhrij":"رواه البخاري ومسلم"}
        """.data(using: .utf8)!
        let h = try JSONDecoder().decode(Hadith.self, from: json)
        #expect(h.number == 1)
        #expect(h.id == 1)
        #expect(h.title == "الحديث الأول")
        #expect(h.body.count == 2)
        #expect(h.body[0].role == .isnad)
        #expect(h.body[1].role == .matn)
        #expect(h.takhrij == "رواه البخاري ومسلم")
    }

    @Test func fragmentFlagsAreStored() {
        let frag = HadithFragment(hadithNumber: 3, title: "الحديث الثالث",
                                  words: [], takhrij: "رواه مسلم",
                                  isFirst: true, isLast: false)
        #expect(frag.hadithNumber == 3)
        #expect(frag.isFirst && !frag.isLast)
    }
}
