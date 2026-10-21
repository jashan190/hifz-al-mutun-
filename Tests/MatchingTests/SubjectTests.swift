import Testing
import SwiftUI
@testable import HifzAlMutun

@Suite struct SubjectTests {
    @Test func decodesKnownIdAndFallsBack() throws {
        #expect(Subject(rawValue: "hadith") == .hadith)
        #expect(Subject.from(id: "unknown-xyz") == .quran)   // safe fallback
    }
    @Test func shelfOrderIsStableAndComplete() {
        #expect(Subject.allCases.first == .quran)            // Qur'ān shelf first
        #expect(Subject.allCases.count == 6)
    }
    @Test func everySubjectHasArabicName() {
        for s in Subject.allCases { #expect(!s.arabicName.isEmpty) }
    }
}
