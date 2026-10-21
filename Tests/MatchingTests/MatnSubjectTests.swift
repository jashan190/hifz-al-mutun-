import Testing
import Foundation
@testable import HifzAlMutun

@Suite struct MatnSubjectTests {
    // Minimal canonical-v2 matn JSON with an explicit subject.
    private func json(subject: String?) -> Data {
        let subjLine = subject.map { "\"subject\": \"\($0)\"," } ?? ""
        return """
        {
          "schemaVersion": 2, \(subjLine)
          "id": "x", "title": "س", "titleLatin": "x", "author": "a", "meter": "m",
          "baytsPerPage": 10, "pageCount": 1, "baytCount": 1,
          "pages": [{"page": 1, "items": []}],
          "babs": []
        }
        """.data(using: .utf8)!
    }

    @Test func decodesExplicitSubject() throws {
        let m = try JSONDecoder().decode(Matn.self, from: json(subject: "hadith"))
        #expect(m.subject == .hadith)
    }
    @Test func missingSubjectFallsBackToQuran() throws {
        let m = try JSONDecoder().decode(Matn.self, from: json(subject: nil))
        #expect(m.subject == .quran)
    }
}
