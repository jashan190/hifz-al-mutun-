import Testing
import SwiftUI
@testable import HifzAlMutun

@Suite struct MistakeBoxTests {
    @Test func renderBoxesFlaggedWordWithBackground() {
        // "في النظم" → two words; box the second (range of "النظم").
        let plain = "في النظم"
        let ranges = HemistichReveal.wordRanges(in: plain)
        let rendered = HemistichText.render(
            segments: [Segment(text: plain, color: .black, footnote: nil)],
            plain: plain, size: 30, justifyWidth: 200,
            tint: { _ in Theme.ink },
            boxed: [ranges[1]])
        // Somewhere in the base string, a run carries the box background colour.
        let hasBox = rendered.base.runs.contains { $0.backgroundColor != nil }
        #expect(hasBox)
    }
}
