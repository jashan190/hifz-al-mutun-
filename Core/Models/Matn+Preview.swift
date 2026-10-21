import Foundation

#if DEBUG
extension Matn {
    /// Sample matn for SwiftUI previews. Loads a bundled file (Tuhfa, via the
    /// legacy→canonical path), with a tiny inline fallback so previews never
    /// crash if resources aren't present.
    static let preview: Matn = {
        if let url = Bundle.main.url(forResource: "tuhfa", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let matn = try? JSONDecoder().decode(Matn.self, from: data) {
            return matn
        }
        return fallback
    }()

    private static let fallback: Matn = {
        func seg(_ s: String, _ c: SegmentColor = .black) -> Segment {
            Segment(text: s, color: c, footnote: nil)
        }
        func word(_ s: String) -> Word { Word(text: s, normalized: s) }

        let sadr = Hemistich(
            text: "يَقُولُ رَاجِي رَحْمَةِ الْغَفُورِ",
            segments: [seg("يَقُولُ رَاجِي رَحْمَةِ الْغَفُورِ")],
            words: ["يَقُولُ", "رَاجِي", "رَحْمَةِ", "الْغَفُورِ"].map(word)
        )
        let ajuz = Hemistich(
            text: "دَوْمًا سُلَيْمَانُ هُوَ الْجَمْزُورِي",
            segments: [
                seg("دَوْمًا "),
                seg("سُلَيْمَانُ", .red),
                seg(" هُوَ "),
                seg("الْجَمْزُورِي", .red),
            ],
            words: ["دَوْمًا", "سُلَيْمَانُ", "هُوَ", "الْجَمْزُورِي"].map(word)
        )
        let bayt = Bayt(number: 1, sadr: sadr, ajuz: ajuz)
        let page = MatnPage(page: 1, items: [
            .heading(Heading(text: "المقدمة", segments: [seg("المقدمة")])),
            .bayt(bayt),
        ])
        return Matn(
            id: "sample", title: "تحفة الأطفال",
            fullTitle: "تحفة الأطفال والغلمان",
            titleLatin: "Tuhfat al-Atfal", author: "", meter: "", subject: .quran,
            baytsPerPage: 10, pageCount: 1, baytCount: 1,
            pages: [page],
            babs: [Bab(id: "b", title: "المقدمة", startPage: 1)],
            reviewNotes: []
        )
    }()
}
#endif
