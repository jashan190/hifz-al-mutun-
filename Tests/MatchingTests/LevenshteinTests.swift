import Testing
@testable import HifzAlMutun

@Suite struct LevenshteinTests {
    @Test func identicalIsZero() { #expect(levenshtein("يقول", "يقول") == 0) }
    @Test func oneSubstitution() { #expect(levenshtein("يقول", "يقيل") == 1) }
    @Test func oneInsertion() { #expect(levenshtein("قول", "يقول") == 1) }
    @Test func emptyVsWord() { #expect(levenshtein("", "يقول") == 4) }
}
