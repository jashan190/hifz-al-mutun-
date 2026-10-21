import Testing
import UIKit
@testable import HifzAlMutun

@Suite struct DisplayFontTests {
    @Test func arefRuqaaIsBundledAndRegistered() {
        PageFont.registerBundledFonts()
        #expect(UIFont(name: "Aref Ruqaa", size: 20) != nil)
    }
}
