import Testing
@testable import HifzAlMutun

@MainActor
@Suite struct RecitationSessionTests {
    private func index() -> RecitationIndex {
        func hemi(_ w: [String]) -> Hemistich {
            Hemistich(text: w.joined(separator: " "),
                      segments: [Segment(text: w.joined(separator: " "), color: .black, footnote: nil)],
                      words: w.map { Word(text: $0, normalized: ArabicNormalize.normalize($0)) })
        }
        let b = Bayt(number: 1, sadr: hemi(["يقول", "راجي"]), ajuz: hemi(["عفو", "رب"]))
        return RecitationIndex(matn: Matn(id: "t", title: "t", fullTitle: nil, titleLatin: "t",
            author: "a", meter: "m", baytsPerPage: 1, pageCount: 1, baytCount: 1,
            pages: [MatnPage(page: 1, items: [.bayt(b)])], babs: [], reviewNotes: []))
    }

    @Test func advancesCursorFromMockFragments() async {
        let mock = MockSpeechSource(script: [
            .init(text: "يقول", isFinal: true),
            .init(text: "راجي", isFinal: true),
        ])
        let session = RecitationSession(index: index(), source: mock, startWordIndex: 0)
        try? await mock.start()   // buffers both fragments, then finishes the stream
        await session.run()       // drains the buffered fragments into the tracker
        #expect(session.cursor == 2)
        #expect(session.reveal.revealedWords(bayt: 1, half: .sadr) == 2)
    }
}
