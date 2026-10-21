import Testing
import Foundation
@testable import HifzAlMutun

@Suite struct ReadingPositionTests {
    @Test func recordsAndReadsMostRecentMatn() {
        let d = UserDefaults.standard
        d.removeObject(forKey: "lastOpenedMatn")
        #expect(ReadingPosition.mostRecentMatnID == nil)
        ReadingPosition.recordOpened("jazariyya")
        #expect(ReadingPosition.mostRecentMatnID == "jazariyya")
        ReadingPosition.recordOpened("shatibiyya")
        #expect(ReadingPosition.mostRecentMatnID == "shatibiyya")
    }
}
