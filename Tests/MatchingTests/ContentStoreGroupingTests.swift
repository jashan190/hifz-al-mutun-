import Testing
@testable import HifzAlMutun

@MainActor
@Suite struct ContentStoreGroupingTests {
    @Test func groupsBundledMatnsUnderSubjectsInShelfOrder() {
        let store = ContentStore()
        let shelves = store.shelves
        // Shelves follow Subject.allCases order and skip empty subjects.
        let subjects = shelves.map(\.subject)
        #expect(subjects == subjects.sorted { a, b in
            Subject.allCases.firstIndex(of: a)! < Subject.allCases.firstIndex(of: b)!
        })
        // Every bundled matn appears in exactly one shelf.
        let flat = shelves.flatMap(\.matns)
        #expect(flat.count == store.matns.count)
        // Within a shelf, shortest first (existing convention).
        for shelf in shelves {
            #expect(shelf.matns == shelf.matns.sorted { $0.baytCount < $1.baytCount })
        }
    }
}
